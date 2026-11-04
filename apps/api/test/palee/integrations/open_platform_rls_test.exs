defmodule Palee.Integrations.OpenPlatformRLSTest do
  @moduledoc """
  ADR-378..381 under real Row Level Security: the suite's owner role
  bypasses RLS, so this switches the sandbox transaction to the
  non-superuser runtime role and drives keys, webhooks, consents and doors
  through the real context code. A box sees only its own rows; the
  SECURITY DEFINER lookups (a key's box, a door's box, boxes with due
  deliveries) work before any tenant context exists.
  """

  use Palee.DataCase, async: false

  import Palee.TestFixtures

  alias Palee.{Access, Integrations, Organizations, RLSCase}

  setup do
    RLSCase.ensure_runtime_role!()

    boxes =
      for name <- ["RLS Open A", "RLS Open B"] do
        {:ok, organization} =
          Organizations.create_organization(%{
            name: "#{name} #{System.unique_integer([:positive])}"
          })

        owner = user_fixture()

        {:ok, _membership} =
          Organizations.add_membership(%{
            organization_id: organization.id,
            user_id: owner.id,
            role: :owner,
            status: :active,
            joined_at: DateTime.utc_now()
          })

        {:ok, location} =
          Repo.query(
            "INSERT INTO facility_locations (id, organization_id, name, inserted_at, updated_at) " <>
              "VALUES ($1, $2, 'Κεντρικό', now(), now()) RETURNING id",
            [Ecto.UUID.dump!(Ecto.UUID.generate()), Ecto.UUID.dump!(organization.id)]
          )

        %{rows: [[location_id]]} = location
        %{organization: organization, owner: owner, location_id: Ecto.UUID.load!(location_id)}
      end

    %{a: Enum.at(boxes, 0), b: Enum.at(boxes, 1)}
  end

  defp context(box), do: %{organization_id: box.organization.id, user_id: box.owner.id}

  test "keys, webhooks, consents and doors stay inside their box", %{a: a, b: b} do
    now = DateTime.utc_now()
    Repo.query!("SET LOCAL ROLE #{RLSCase.runtime_role()}")

    assert %{rows: [[false]]} =
             Repo.query!("SELECT rolbypassrls FROM pg_roles WHERE rolname = current_user")

    # A key is found from its token alone, then only in its own box.
    {:ok, %{key: key, token: token}} =
      Integrations.create_api_key(
        context(a),
        %{name: "Zap", scopes: ["members:read"]},
        a.owner.id,
        now
      )

    assert {:ok, %{organization_id: org_id, key: %{id: key_id}}} =
             Integrations.authenticate(token, now)

    assert org_id == a.organization.id
    assert key_id == key.id
    assert [_one] = Integrations.list_api_keys(context(a))
    assert [] = Integrations.list_api_keys(context(b))
    assert {:error, :not_found} = Integrations.revoke_api_key(context(b), key.id, b.owner.id, now)

    # A webhook outbox row is due in box A only.
    {:ok, %{endpoint: endpoint}} =
      Integrations.create_endpoint(
        context(a),
        %{url: "https://hooks.example.com/a", events: ["booking.created"]},
        a.owner.id
      )

    assert {:ok, 1} =
             Integrations.enqueue_event(
               context(a),
               "booking.created",
               %{booking_id: "x"},
               Ecto.UUID.generate(),
               now,
               now
             )

    assert {:ok, 0} =
             Integrations.enqueue_event(
               context(b),
               "booking.created",
               %{},
               Ecto.UUID.generate(),
               now,
               now
             )

    assert a.organization.id in Integrations.due_organizations(DateTime.add(now, 1, :second))
    refute b.organization.id in Integrations.due_organizations(DateTime.add(now, 1, :second))
    assert {:error, :not_found} = Integrations.get_endpoint(context(b), endpoint.id)

    # Consent is the member's own row of that box.
    assert {:ok, %{granted: true}} =
             Integrations.set_consent(context(a), a.owner.id, true, "member_app", now)

    assert %{granted: false} = Integrations.consent(context(b), a.owner.id)

    # A door's box is found from the event URL, its log stays in the box.
    {:ok, %{door: door, event_token: event_token}} =
      Access.create_door(
        context(a),
        %{name: "Είσοδος", location_id: a.location_id, provider: "sandbox"},
        a.owner.id
      )

    assert {:ok, 1} = Access.ingest_event(door.id, event_token, %{"event" => "door_opened"}, now)
    assert {:error, :not_found} = Access.ingest_event(door.id, "wrong", %{"event" => "x"}, now)
    assert %{total: 1} = Access.list_events(context(a), %{})
    assert %{total: 0} = Access.list_events(context(b), %{})
    assert [] = Access.list_doors(context(b), %{})

    # A door cannot point at another box's branch (composite foreign key).
    assert {:error, _refused} =
             Access.create_door(
               context(b),
               %{name: "Ξένη", location_id: a.location_id, provider: "sandbox"},
               b.owner.id
             )
  end
end

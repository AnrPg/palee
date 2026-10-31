defmodule Palee.AiHelpFixtures do
  @moduledoc """
  ADR-361..363 test data: a box with an owner, members with and without
  recent visits, a package with payments and an expiring subscription, and
  classes with attendance. Rows are written directly (the test role
  bypasses row security), always with the box's id.
  """

  import Palee.TestFixtures

  alias Palee.{AiUsage, Organizations, Repo}

  @owner_capabilities Organizations.Domain.AccessPolicy.capabilities([:owner])

  def owner_capabilities, do: @owner_capabilities

  @doc "A box with an owner; returns `%{organization, owner, context}`."
  def box_fixture(opts \\ []) do
    owner = admin_fixture()

    {:ok, organization} =
      Organizations.create_organization(%{name: "AI box #{System.unique_integer([:positive])}"})

    {:ok, _} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: owner.id,
        role: :owner,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    context = %{
      organization_id: organization.id,
      user_id: owner.id,
      capabilities: Keyword.get(opts, :capabilities, @owner_capabilities)
    }

    if Keyword.get(opts, :enabled, true) do
      {:ok, _} = AiUsage.put_settings(context, %{data_questions_enabled: true})
    end

    %{organization: organization, owner: owner, context: context}
  end

  @doc "Adds a box member (staff-visible name) and returns the user."
  def member_fixture(%{organization: organization}, name, opts \\ []) do
    user = user_fixture(%{nickname: name})

    sql!(
      """
      INSERT INTO memberships (id, organization_id, user_id, user_type_snapshot, status, signup_source,
        starts_on, inserted_at, updated_at)
      VALUES (gen_random_uuid(), $1, $2, 'member', 'active', 'admin_created', $3, now(), now())
      """,
      [uuid(organization.id), uuid(user.id), Keyword.get(opts, :starts_on, Date.utc_today())]
    )

    user
  end

  @doc "A class `days_ago` days back with these users attending."
  def class_fixture(%{organization: organization}, type_name, days_ago, attendees, capacity \\ 10) do
    type_id = Ecto.UUID.generate()
    class_id = Ecto.UUID.generate()

    sql!(
      "INSERT INTO class_types (id, organization_id, name, slug, inserted_at, updated_at) VALUES ($1, $2, $3, $4, now(), now()) ON CONFLICT DO NOTHING",
      [uuid(type_id), uuid(organization.id), type_name, "#{String.downcase(type_name)}-#{System.unique_integer([:positive])}"]
    )

    sql!(
      "INSERT INTO scheduled_classes (id, organization_id, class_type_id, scheduled_at, capacity, inserted_at, updated_at) VALUES ($1, $2, $3, now() - make_interval(days => $4), $5, now(), now())",
      [uuid(class_id), uuid(organization.id), uuid(type_id), days_ago, capacity]
    )

    for user <- attendees do
      sql!(
        "INSERT INTO class_attendance_records (id, organization_id, scheduled_class_id, user_id, status, marked_at, inserted_at, updated_at) VALUES (gen_random_uuid(), $1, $2, $3, 'attended', now(), now(), now())",
        [uuid(organization.id), uuid(class_id), uuid(user.id)]
      )
    end

    class_id
  end

  @doc "A package, one subscription of `user` ending `ends_in` days from today, and paid payments."
  def package_fixture(%{organization: organization}, user, name, payments, ends_in \\ 5) do
    package_id = Ecto.UUID.generate()
    subscription_id = Ecto.UUID.generate()

    sql!(
      "INSERT INTO membership_packages (id, organization_id, code, name, family, billing_period, base_price_cents, currency, inserted_at, updated_at) VALUES ($1, $2, $3, $4, 'membership', 'monthly', 5000, 'EUR', now(), now())",
      [uuid(package_id), uuid(organization.id), "pkg-#{System.unique_integer([:positive])}", name]
    )

    [[membership_id]] =
      sql!("SELECT id FROM memberships WHERE organization_id = $1 AND user_id = $2", [
        uuid(organization.id),
        uuid(user.id)
      ]).rows

    sql!(
      """
      INSERT INTO membership_package_subscriptions (id, organization_id, membership_id, membership_package_id,
        status, starts_on, ends_on, package_code_snapshot, package_family_snapshot, billing_period_snapshot,
        auto_renew, inserted_at, updated_at)
      VALUES ($1, $2, $3, $4, 'active', $5, $6, 'pkg', 'membership', 'monthly', false, now(), now())
      """,
      [uuid(subscription_id), uuid(organization.id), membership_id, uuid(package_id), Date.add(Date.utc_today(), -25), Date.add(Date.utc_today(), ends_in)]
    )

    for {cents, paid_on} <- payments do
      sql!(
        """
        INSERT INTO membership_payments (id, organization_id, membership_id, membership_package_subscription_id,
          amount_cents, currency, paid_on, payment_method, payment_status, inserted_at, updated_at)
        VALUES (gen_random_uuid(), $1, $2, $3, $4, 'EUR', $5, 'cash', 'paid', now(), now())
        """,
        [uuid(organization.id), membership_id, uuid(subscription_id), cents, paid_on]
      )
    end

    package_id
  end

  defp sql!(sql, params), do: Repo.query!(sql, params)
  defp uuid(id), do: Ecto.UUID.dump!(id)
end

defmodule Palee.ActivityLogTest do
  @moduledoc """
  ADR-760: entries are insert-only (8A) and a box sees only its own; the one
  update the table allows is forgetting a deleted person (9A).
  """
  use Palee.DataCase, async: false

  import Palee.TestFixtures

  alias Palee.{ActivityLog, Organizations, Repo}
  alias Palee.Infrastructure.Tenancy.RepoContext

  setup do
    owner = user_fixture(%{role: :member, nickname: "al_owner"})
    member = user_fixture(%{role: :member, nickname: "al_member"})

    {:ok, organization} =
      Organizations.create_organization(%{name: "AL #{System.unique_integer([:positive])}"})

    for {user, role} <- [{owner, :owner}, {member, :member}] do
      {:ok, _} =
        Organizations.add_membership(%{
          organization_id: organization.id,
          user_id: user.id,
          role: role,
          status: :active,
          joined_at: DateTime.utc_now()
        })
    end

    {:ok, context} = Organizations.resolve_tenant_context(owner, organization.slug)
    %{owner: owner, member: member, organization: organization, context: context}
  end

  defp record!(ctx, attrs \\ %{}) do
    {:ok, entry} =
      ActivityLog.record(
        ctx.context,
        Map.merge(
          %{action: "package.freeze", person_user_id: ctx.member.id, reason: "Knee"},
          attrs
        )
      )

    entry
  end

  test "an entry can be neither changed nor deleted", ctx do
    entry = record!(ctx)

    RepoContext.run(%{organization_id: ctx.organization.id}, fn ->
      assert_raise Postgrex.Error, ~r/insert-only/, fn ->
        Repo.query!("UPDATE activity_log_entries SET reason = 'other' WHERE id = $1", [
          Ecto.UUID.dump!(entry.id)
        ])
      end
    end)
  end

  test "forgetting a person keeps the action and drops reason and details", ctx do
    entry = record!(ctx, %{details: %{"note" => "x"}})

    RepoContext.run(%{organization_id: ctx.organization.id}, fn ->
      %{num_rows: 1} =
        Repo.query!(
          "UPDATE activity_log_entries SET reason = NULL, details = '{}'::jsonb, redacted_at = now() WHERE id = $1",
          [Ecto.UUID.dump!(entry.id)]
        )
    end)

    {:ok, %{entries: [row]}} = ActivityLog.list(ctx.context, %{})
    assert row.action == "package.freeze"
    assert row.reason == nil
    assert row.redacted
  end

  test "forget_person changes nothing without a scheduled deletion", ctx do
    record!(ctx)
    assert :ok = ActivityLog.forget_person(ctx.member.id)
    {:ok, %{entries: [row]}} = ActivityLog.list(ctx.context, %{})
    assert row.reason == "Knee"
  end

  test "another box sees none of the entries", ctx do
    record!(ctx)
    other = user_fixture(%{role: :member, nickname: "al_other"})

    {:ok, org2} =
      Organizations.create_organization(%{name: "AL2 #{System.unique_integer([:positive])}"})

    {:ok, _} =
      Organizations.add_membership(%{
        organization_id: org2.id,
        user_id: other.id,
        role: :owner,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    {:ok, context2} = Organizations.resolve_tenant_context(other, org2.slug)
    assert {:ok, %{entries: []}} = ActivityLog.list(context2, %{})
  end

  test "an unknown action is refused", ctx do
    assert {:error, _} = ActivityLog.record(ctx.context, %{action: "nope.nothing"})
  end
end

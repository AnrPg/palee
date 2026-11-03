defmodule Palee.ReviewAsks.EctoReviewSignalsTest do
  @moduledoc "ADR-355: the facts behind a review ask come from the box's own tables."

  use Palee.DataCase, async: false

  import Palee.TestFixtures

  alias Palee.Infrastructure.ReviewAsks.EctoReviewSignals
  alias Palee.Organizations

  test "a new member without classes or a paid membership" do
    member = user_fixture()

    {:ok, organization} =
      Organizations.create_organization(%{name: "Signals #{System.unique_integer([:positive])}"})

    joined = ~U[2026-01-05 09:00:00.000000Z]

    {:ok, _membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: member.id,
        role: :member,
        status: :active,
        joined_at: joined
      })

    {:ok, context} = Organizations.resolve_tenant_context(member, organization.slug)

    assert %{
             active_membership: false,
             attendance_count: 0,
             last_attended_at: nil,
             member_since: ^joined
           } = EctoReviewSignals.facts(context, member.id)
  end
end

defmodule Palee.Retention.Domain.RiskScoreTest do
  use ExUnit.Case, async: true

  alias Palee.Retention.Domain.RiskScore

  @steady %{
    visits_recent: 12,
    visits_baseline: 24,
    days_since_last_visit: 2,
    upcoming_bookings: 3,
    cancellations_recent: 0,
    package_ends_in_days: 40,
    package_renews: true,
    overdue_invoices: 0,
    member_for_days: 400
  }

  test "a steady member is low risk with no reasons" do
    assert %{score: 0, level: "low", reasons: [], suggested_action: "none"} = RiskScore.score(@steady)
  end

  test "a member who stopped coming is high risk, with every reason explained" do
    result =
      RiskScore.score(%{
        @steady
        | visits_recent: 1,
          days_since_last_visit: 23,
          upcoming_bookings: 0
      })

    assert result.level == "high"
    assert [%{code: "attendance_drop", points: 37} = drop, %{code: "absent", points: 35} | _] =
             result.reasons
    assert drop.facts == %{"per_week_now" => 0.3, "per_week_usual" => 3.0}
    assert Enum.any?(result.reasons, &(&1.code == "no_upcoming_bookings"))
    assert result.score == Enum.sum(Enum.map(result.reasons, & &1.points))
    assert result.suggested_action == "personal_message"
  end

  test "a package ending without renewal and an overdue invoice suggest the money conversation" do
    result = RiskScore.score(%{@steady | package_ends_in_days: 3, package_renews: false, overdue_invoices: 1})

    assert result.level == "medium"
    assert [%{code: "package_ending"}, %{code: "payment_overdue"}] = result.reasons
    assert result.suggested_action == "renewal_offer"
  end

  test "a new box member who never came gets a call" do
    result =
      RiskScore.score(%{
        visits_recent: 0,
        visits_baseline: 0,
        days_since_last_visit: nil,
        upcoming_bookings: 0,
        member_for_days: 20
      })

    assert [%{code: "no_first_visit", points: 30}] = result.reasons
    assert result.suggested_action == "check_in_call"
  end

  test "the score never passes 100" do
    result =
      RiskScore.score(%{
        visits_recent: 0,
        visits_baseline: 40,
        days_since_last_visit: 60,
        upcoming_bookings: 0,
        cancellations_recent: 5,
        package_ends_in_days: 1,
        package_renews: false,
        overdue_invoices: 2,
        member_for_days: 500
      })

    assert result.score == 100
  end
end

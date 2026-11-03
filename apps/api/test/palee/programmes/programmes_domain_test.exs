defmodule Palee.Programmes.DomainTest do
  @moduledoc "ADR-370/371: the pure rules of programmes, purchases, refunds and reviews."
  use ExUnit.Case, async: true

  alias Palee.Programmes.Domain.{
    ProgrammePolicy,
    ProgrammeSchedule,
    PurchaseLifecycle,
    RefundRules,
    ReviewPolicy
  }

  @w1 "00000000-0000-0000-0000-000000000001"
  @w2 "00000000-0000-0000-0000-000000000002"

  describe "ProgrammePolicy.normalize_days/2" do
    test "sorts days, accepts atom or string keys" do
      assert {:ok, [%{"day" => 0, "workout_id" => @w2}, %{"day" => 6, "workout_id" => @w1}]} =
               ProgrammePolicy.normalize_days(
                 [%{day: 6, workout_id: @w1}, %{"day" => 0, "workout_id" => @w2}],
                 1
               )
    end

    test "refuses days outside the weeks, duplicates, bad ids and crowded days" do
      for days <- [
            [%{day: 7, workout_id: @w1}],
            [%{day: -1, workout_id: @w1}],
            [%{day: 0, workout_id: "nope"}],
            [%{day: 0, workout_id: @w1}, %{day: 0, workout_id: @w1}],
            [],
            Enum.map(1..5, fn n ->
              %{day: 0, workout_id: "00000000-0000-0000-0000-00000000000#{n}"}
            end)
          ] do
        assert {:error, :invalid_programme_days} = ProgrammePolicy.normalize_days(days, 1)
      end

      assert {:error, :invalid_programme_days} =
               ProgrammePolicy.normalize_days([%{day: 0, workout_id: @w1}], 53)
    end

    test "workout ids are unique and in order" do
      days = [
        %{"day" => 0, "workout_id" => @w1},
        %{"day" => 1, "workout_id" => @w2},
        %{"day" => 2, "workout_id" => @w1}
      ]

      assert ProgrammePolicy.workout_ids(days) == [@w1, @w2]
    end
  end

  describe "ProgrammePolicy publishing and sale" do
    @programme %{
      status: "draft",
      price_cents: 4_900,
      currency: "EUR",
      listing: "marketplace",
      current_version_id: nil
    }

    test "a paid programme with days publishes" do
      assert :ok = ProgrammePolicy.publishable(@programme, [%{"day" => 0}])

      assert {:error, :programme_price_required} =
               ProgrammePolicy.publishable(%{@programme | price_cents: 0}, [%{}])

      assert {:error, :invalid_programme_days} = ProgrammePolicy.publishable(@programme, [])
    end

    test "on sale only when published, paid and versioned" do
      refute ProgrammePolicy.on_sale?(@programme)
      published = %{@programme | status: "published", current_version_id: @w1}
      assert ProgrammePolicy.on_sale?(published)
      assert ProgrammePolicy.in_marketplace?(published)
      refute ProgrammePolicy.in_marketplace?(%{published | listing: "box"})
    end

    test "archive and restore" do
      now = DateTime.utc_now()

      assert {:ok, %{status: "archived"}} =
               ProgrammePolicy.transition(%{status: "published"}, :archive, now)

      assert {:ok, %{status: "published"}} =
               ProgrammePolicy.transition(
                 %{status: "archived", current_version_id: @w1},
                 :restore,
                 now
               )

      assert {:error, :invalid_programme_transition} =
               ProgrammePolicy.transition(%{status: "draft"}, :archive, now)
    end

    test "preview shows only the first days" do
      days = [%{"day" => 0}, %{"day" => 2}, %{"day" => 3}]
      assert [%{"day" => 0}, %{"day" => 2}] = ProgrammePolicy.preview(days, 3)
      assert [] = ProgrammePolicy.preview(days, 0)
    end
  end

  describe "ProgrammeSchedule.dates/3" do
    test "day n falls on start + n, past days are not back-filled" do
      days = [%{"day" => 0, "workout_id" => @w1}, %{"day" => 3, "workout_id" => @w2}]
      start = ~D[2027-06-07]

      assert [{~D[2027-06-07], 0, @w1}, {~D[2027-06-10], 3, @w2}] =
               ProgrammeSchedule.dates(days, start, start)

      assert [{~D[2027-06-10], 3, @w2}] = ProgrammeSchedule.dates(days, start, ~D[2027-06-08])
      assert %{week: 2, weekday: 1} = ProgrammeSchedule.position(8)
    end
  end

  describe "RefundRules" do
    @now ~U[2027-06-01 10:00:00Z]

    defp purchase(attrs) do
      Map.merge(
        %{
          status: "active",
          price_cents: 7_000,
          refunded_cents: 0,
          refund_policy: "withdrawal_only",
          starts_on: ~D[2027-06-01],
          ends_on: ~D[2027-06-28],
          withdrawal: %{"applies" => true, "deadline" => "2027-06-15T10:00:00Z"}
        },
        attrs
      )
    end

    test "start date window" do
      assert :ok = RefundRules.check_start(~D[2027-06-01], ~D[2027-06-01])
      assert :ok = RefundRules.check_start(~D[2027-07-31], ~D[2027-06-01])

      assert {:error, :invalid_start_date} =
               RefundRules.check_start(~D[2027-05-31], ~D[2027-06-01])

      assert {:error, :invalid_start_date} =
               RefundRules.check_start(~D[2027-08-01], ~D[2027-06-01])

      assert RefundRules.ends_on(~D[2027-06-01], 4) == ~D[2027-06-28]
    end

    test "withdrawal returns the part not yet provided, within 14 days" do
      # 28 days, 7 used → 3/4 back.
      assert {:ok, %{amount_cents: 5_250, rule: "withdrawal"}} =
               RefundRules.quote(purchase(%{}), ~D[2027-06-08], @now)

      assert {:error, :programme_refund_not_available} =
               RefundRules.quote(purchase(%{}), ~D[2027-06-16], ~U[2027-06-16 10:00:00Z])
    end

    test "no withdrawal right and no seller rule: nothing" do
      assert {:error, :programme_refund_not_available} =
               RefundRules.quote(
                 purchase(%{withdrawal: %{"applies" => false}}),
                 ~D[2027-06-02],
                 @now
               )
    end

    test "the seller's rule adds to the law, the larger amount wins" do
      future =
        purchase(%{
          refund_policy: "before_start",
          starts_on: ~D[2027-07-01],
          ends_on: ~D[2027-07-28],
          withdrawal: %{}
        })

      assert {:ok, %{amount_cents: 7_000, rule: "before_start"}} =
               RefundRules.quote(future, ~D[2027-06-20], @now)

      late =
        purchase(%{
          refund_policy: "pro_rata",
          withdrawal: %{"applies" => true, "deadline" => "2027-06-02T00:00:00Z"}
        })

      assert {:ok, %{amount_cents: 1_750, rule: "pro_rata"}} =
               RefundRules.quote(late, ~D[2027-06-22], ~U[2027-06-22 10:00:00Z])
    end

    test "never more than what is left, and only active purchases" do
      assert {:ok, %{amount_cents: 1_000}} =
               RefundRules.quote(purchase(%{refunded_cents: 6_000}), ~D[2027-06-01], @now)

      assert {:error, :programme_refund_not_available} =
               RefundRules.quote(purchase(%{status: "withdrawn"}), ~D[2027-06-01], @now)
    end

    test "staff refunds fit what is left" do
      p = purchase(%{refunded_cents: 5_000})
      assert :ok = RefundRules.check_staff_amount(p, 2_000)
      assert {:error, :refund_exceeds_remaining} = RefundRules.check_staff_amount(p, 2_001)
      assert {:error, :invalid_refund_amount} = RefundRules.check_staff_amount(p, 0)
    end
  end

  describe "PurchaseLifecycle" do
    @now ~U[2027-06-01 10:00:00Z]

    test "paid activates, refunds end it" do
      assert {:ok, %{status: "active", finance_payment_id: "fp"}} =
               PurchaseLifecycle.transition(
                 %{status: "pending_payment"},
                 {:paid, %{finance_payment_id: "fp"}},
                 @now
               )

      active = %{status: "active", price_cents: 100, refunded_cents: 0}

      assert {:ok, %{status: "withdrawn", refunded_cents: 60}} =
               PurchaseLifecycle.transition(active, {:refunded, 60, :withdrawal}, @now)

      assert {:ok, %{refunded_cents: 40} = partial} =
               PurchaseLifecycle.transition(active, {:refunded, 40, :staff}, @now)

      refute Map.has_key?(partial, :status)

      assert {:ok, %{status: "refunded"}} =
               PurchaseLifecycle.transition(active, {:refunded, 100, :staff}, @now)

      assert {:error, :invalid_purchase_transition} =
               PurchaseLifecycle.transition(%{status: "cancelled"}, {:paid, %{}}, @now)
    end
  end

  describe "ReviewPolicy" do
    test "buyers review once started" do
      assert :ok =
               ReviewPolicy.may_review(
                 %{status: "active", starts_on: ~D[2027-06-01]},
                 ~D[2027-06-01]
               )

      assert {:error, :review_too_early} =
               ReviewPolicy.may_review(
                 %{status: "active", starts_on: ~D[2027-06-02]},
                 ~D[2027-06-01]
               )

      assert {:error, :review_not_allowed} =
               ReviewPolicy.may_review(
                 %{status: "withdrawn", starts_on: ~D[2027-06-01]},
                 ~D[2027-06-09]
               )
    end

    test "rating 1..5 and a short text" do
      assert {:ok, %{rating: 5, body: nil}} = ReviewPolicy.normalize(%{rating: 5, body: "  "})
      assert {:error, :invalid_review} = ReviewPolicy.normalize(%{rating: 6})

      assert {:error, :invalid_review} =
               ReviewPolicy.normalize(%{rating: 3, body: String.duplicate("a", 1_001)})

      assert {:ok, "spam"} = ReviewPolicy.hide_reason("spam")
      assert {:error, :invalid_hide_reason} = ReviewPolicy.hide_reason("dislike")
    end

    test "summary counts published reviews only" do
      assert %{average: 4.5, count: 2} =
               ReviewPolicy.summary([
                 %{status: "published", rating: 5},
                 %{status: "published", rating: 4},
                 %{status: "hidden", rating: 1}
               ])
    end
  end
end

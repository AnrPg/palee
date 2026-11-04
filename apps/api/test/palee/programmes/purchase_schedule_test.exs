defmodule Palee.Programmes.Domain.PurchaseScheduleTest do
  @moduledoc "ADR-540: a bought programme as a sequence of days («Έμεινε πίσω»)."
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Palee.Programmes.Domain.{PurchaseSchedule, RefundRules}

  @start ~D[2027-01-04]

  defp version(days, weeks \\ 2),
    do: %{weeks: weeks, days: Enum.map(days, &%{"day" => &1, "workout_id" => "w#{&1}"})}

  defp purchase(attrs \\ %{}) do
    Map.merge(
      %{
        starts_on: @start,
        ends_on: Date.add(@start, 13),
        planned_ends_on: Date.add(@start, 13),
        day_dates: %{},
        skipped_days: []
      },
      attrs
    )
  end

  defp status(days, day), do: Enum.find(days, &(&1.day == day)).status
  defp date(days, day), do: Enum.find(days, &(&1.day == day)).date

  test "days have dates and statuses; days without WODs are rest" do
    days = PurchaseSchedule.days(version([0, 2, 4, 9]), purchase(), [0], Date.add(@start, 4))

    assert length(days) == 14
    assert status(days, 0) == "done"
    assert status(days, 1) == "rest"
    assert status(days, 2) == "behind"
    assert status(days, 4) == "today"
    assert status(days, 9) == "upcoming"
    assert date(days, 9) == Date.add(@start, 9)
    assert %{week: 2, weekday: 2} = Enum.find(days, &(&1.day == 9))

    assert PurchaseSchedule.progress(days) ==
             %{total: 4, done: 1, skipped: 0, behind: 1, remaining: 3}

    assert %{day: 2} = PurchaseSchedule.next_behind(days)
  end

  test "«Κάν' τη σήμερα» moves the day to today and shifts the rest that are not done" do
    today = Date.add(@start, 3)
    p = purchase()
    # Day 4 was already done ahead of time: it keeps its date.
    days = PurchaseSchedule.days(version([0, 2, 4, 9]), p, [0, 4], today)

    assert {:ok, %{day_dates: day_dates, ends_on: ends_on, moves: moves}} =
             PurchaseSchedule.do_today(days, p, 2, today)

    assert Enum.map(moves, & &1.day) == [2, 9]
    assert day_dates == %{"2" => "2027-01-07", "9" => "2027-01-14"}
    # The last day (a rest day after day 9) moved with it.
    assert ends_on == Date.add(@start, 14)

    moved = %{p | day_dates: day_dates}
    after_move = PurchaseSchedule.days(version([0, 2, 4, 9]), moved, [0, 4], today)
    assert status(after_move, 2) == "today"
    assert date(after_move, 4) == Date.add(@start, 4)
    assert date(after_move, 10) == Date.add(@start, 11)
    assert PurchaseSchedule.next_behind(after_move) == nil
  end

  test "only a behind day moves or is skipped; skipping moves nothing" do
    today = Date.add(@start, 3)
    p = purchase()
    days = PurchaseSchedule.days(version([0, 2, 4]), p, [0], today)

    assert {:error, :programme_day_not_behind} = PurchaseSchedule.do_today(days, p, 4, today)
    assert {:error, :programme_day_not_behind} = PurchaseSchedule.do_today(days, p, 0, today)
    assert {:error, :programme_day_not_found} = PurchaseSchedule.do_today(days, p, 1, today)
    assert {:error, :programme_day_not_found} = PurchaseSchedule.do_today(days, p, 99, today)

    assert {:ok, [2]} = PurchaseSchedule.skip(days, p, 2)
    assert {:error, :programme_day_not_behind} = PurchaseSchedule.skip(days, p, 4)

    skipped = %{p | skipped_days: [2]}
    days = PurchaseSchedule.days(version([0, 2, 4]), skipped, [0], today)
    assert status(days, 2) == "skipped"
    assert {:ok, [2]} = PurchaseSchedule.skip(days, skipped, 2)
    assert date(days, 4) == Date.add(@start, 4)
  end

  test "a move never ends the programme after its own length past the planned end" do
    p = purchase()
    # Back after five weeks: moving day 2 to today would end it in week 7.
    today = Date.add(@start, 35)
    days = PurchaseSchedule.days(version([0, 2, 9]), p, [0], today)

    assert PurchaseSchedule.latest_end(p, 2) == Date.add(@start, 27)
    assert {:error, :programme_schedule_limit} = PurchaseSchedule.do_today(days, p, 2, today)
    refute PurchaseSchedule.can_do_today?(days, p, 2, today)
    assert {:ok, [2]} = PurchaseSchedule.skip(days, p, 2)
  end

  test "a purchase from before ADR-540 (no planned end) counts its ends_on as planned" do
    p = purchase(%{planned_ends_on: nil})
    assert PurchaseSchedule.latest_end(p, 2) == Date.add(@start, 27)
  end

  test "refunds count on the planned period, not the moved end" do
    sold = %{price_cents: 1_400, starts_on: @start, ends_on: Date.add(@start, 13)}
    moved = Map.merge(sold, %{ends_on: Date.add(@start, 20), planned_ends_on: sold.ends_on})

    assert RefundRules.unused_cents(moved, Date.add(@start, 7)) ==
             RefundRules.unused_cents(sold, Date.add(@start, 7))
  end

  describe "properties" do
    property "«Κάν' τη σήμερα» keeps the order and gaps of what is left and never moves the past" do
      check all(
              weeks <- integer(1..4),
              days <-
                map(
                  list_of(integer(0..(weeks * 7 - 1)), min_length: 1, max_length: 12),
                  &Enum.uniq/1
                ),
              done <- list_of(member_of(days), max_length: 4),
              offset <- integer(0..(weeks * 7 + 3)),
              max_runs: 200
            ) do
        version = version(days, weeks)
        ends_on = Date.add(@start, weeks * 7 - 1)
        p = purchase(%{ends_on: ends_on, planned_ends_on: ends_on})
        today = Date.add(@start, offset)
        listed = PurchaseSchedule.days(version, p, done, today)

        for %{day: day, status: "behind"} <- listed do
          case PurchaseSchedule.do_today(listed, p, day, today) do
            {:ok, %{day_dates: day_dates, ends_on: new_end}} ->
              moved = %{p | day_dates: day_dates, ends_on: new_end}
              after_move = PurchaseSchedule.days(version, moved, done, today)
              by_day = Map.new(after_move, &{&1.day, &1})
              before = Map.new(listed, &{&1.day, &1})

              assert by_day[day].status == "today"
              assert Date.compare(new_end, ends_on) != :lt
              assert Date.compare(new_end, PurchaseSchedule.latest_end(p, weeks)) != :gt
              assert Date.compare(new_end, List.last(after_move).date) != :lt

              for row <- listed, row.status != "rest" do
                cond do
                  row.day < day or row.status in ["done", "skipped"] ->
                    assert by_day[row.day].date == row.date

                  true ->
                    assert Date.diff(by_day[row.day].date, by_day[day].date) ==
                             Date.diff(row.date, before[day].date)

                    refute by_day[row.day].status == "behind"
                end
              end

            {:error, :programme_schedule_limit} ->
              :ok
          end
        end
      end
    end
  end
end

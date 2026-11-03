defmodule Palee.Application.BookingTerms do
  @moduledoc """
  Booking privileges for a member and class: the member's package terms from
  Finance, falling back to the gym's scheduling defaults (ADR-097).
  """

  alias Palee.{Finance, Organizations, Scheduling}
  alias Palee.Scheduling.Domain.{BookingLimits, BookingPolicy}

  def for_slot(context, user_id, slot) do
    date = Organizations.local_date(context, slot.scheduled_at)
    resolve(finance_terms(context, user_id, date), settings(context))
  end

  @doc """
  The moment each slot stops being free to cancel for this member, or nil when
  no cutoff applies. Terms are read once per gym-local class date, not once
  per slot.
  """
  def cancel_free_until(context, user_id, slots) do
    settings = settings(context)
    date_of = fn slot -> Organizations.local_date(context, slot.scheduled_at) end

    cutoffs =
      slots
      |> Enum.map(date_of)
      |> Enum.uniq()
      |> Map.new(fn date ->
        {date,
         resolve(finance_terms(context, user_id, date), settings).cancellation_cutoff_minutes}
      end)

    Enum.map(slots, fn slot ->
      case cutoffs[date_of.(slot)] do
        minutes when is_integer(minutes) ->
          DateTime.add(slot.scheduled_at, -minutes * 60, :second)

        _ ->
          nil
      end
    end)
  end

  defp resolve(terms, settings) do
    %{
      booking_window_days:
        BookingPolicy.effective_rule(
          terms[:booking_window_days],
          settings[:default_booking_window_days]
        ),
      cancellation_cutoff_minutes:
        BookingPolicy.effective_rule(
          hours_to_minutes(terms[:cancellation_cutoff_hours]),
          settings[:default_cancellation_cutoff_minutes]
        ),
      waitlist_priority: BookingPolicy.waitlist_priority(terms[:waitlist_priority]),
      no_show_penalty_waived: terms[:no_show_penalty_waived] == true,
      # ADR-342: package booking limits (no gym default: a package rule only).
      daily_booking_limit: terms[:daily_booking_limit],
      open_bookings_limit: terms[:open_bookings_limit]
    }
  end

  # ADR-226: packages keep whole hours; the gym default is in minutes.
  def hours_to_minutes(hours) when is_integer(hours), do: hours * 60
  def hours_to_minutes(_none), do: nil

  defp finance_terms(nil, user_id, date), do: Finance.booking_terms(user_id, date)
  defp finance_terms(context, user_id, date), do: Finance.booking_terms(context, user_id, date)

  @doc """
  ADR-342: whether the member's package lets them book one more class at
  `slot`: its daily, weekly and open-bookings limits.
  """
  def check_limits(context, user_id, slot, %DateTime{} = now) do
    terms = for_slot(context, user_id, slot)

    if BookingLimits.any?(terms) do
      zone = zone(context)
      from = BookingLimits.counted_from(slot.scheduled_at, now, zone)
      booked = Scheduling.member_booking_times(context, user_id, from)
      BookingLimits.check(terms, slot.scheduled_at, booked, now, zone)
    else
      :ok
    end
  end

  defp zone(%{organization_id: id}) when is_binary(id),
    do: Organizations.organization_timezone(id)

  defp zone(_context), do: "Etc/UTC"

  defp settings(nil), do: %{}
  defp settings(context), do: Scheduling.get_settings(context)
end

defmodule Palee.Application.CoachPay.WorkSource do
  @moduledoc """
  ADR-341: what coach pay reads from Scheduling, Appointments and Finance,
  through their public APIs, for gym-local dates (ADR-176/179: UTC in
  storage, the gym's zone for the day a class belongs to).
  """

  @behaviour Palee.CoachPay.Ports.WorkSource

  alias Palee.{Appointments, Finance, Organizations, Scheduling}
  alias Palee.TimeZones.ZonedTime

  @impl true
  def classes(context, %Date{} = from, %Date{} = to) do
    zone = zone(context)
    {from_at, to_at} = range(from, to, zone)

    context
    |> Scheduling.coach_classes(from_at, to_at)
    |> Enum.map(fn class ->
      %{
        class_id: class.class_id,
        coach_user_id: class.coach_user_id,
        class_type_id: class.class_type_id,
        name: class.name,
        occurred_on: ZonedTime.local_date(class.scheduled_at, zone),
        attendance: class.attendance
      }
    end)
  end

  @impl true
  def sessions(context, %Date{} = from, %Date{} = to) do
    zone = zone(context)
    {from_at, to_at} = range(from, to, zone)

    context
    |> Appointments.coach_sessions(from_at, to_at)
    |> Enum.map(fn session ->
      %{
        slot_id: session.slot_id,
        coach_user_id: session.coach_user_id,
        kind: session.kind,
        occurred_on: ZonedTime.local_date(session.starts_at, zone),
        bookings: session.bookings
      }
    end)
  end

  @impl true
  def sales(context, %Date{} = from, %Date{} = to), do: Finance.coach_sales(context, from, to)

  defp range(from, to, zone),
    do: {ZonedTime.start_of_day(from, zone), ZonedTime.start_of_day(Date.add(to, 1), zone)}

  defp zone(context), do: Organizations.organization_timezone(context.organization_id)
end

defmodule Palee.Application.CoachPay.WorkSource do
  @moduledoc """
  ADR-341: what coach pay reads from Scheduling, Appointments and Finance,
  through their public APIs, for gym-local dates (ADR-176/179: UTC in
  storage, the gym's zone for the day a class belongs to).
  """

  @behaviour Palee.CoachPay.Ports.WorkSource

  alias Palee.{Appointments, CoachPay, Coaching, Finance, Organizations, Scheduling}
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
        duration_minutes: Map.get(class, :duration_minutes),
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

  @impl true
  def coach_clients(context, %Date{} = from, %Date{} = to) do
    zone = zone(context)
    {from_at, to_at} = range(from, to, zone)

    context
    |> Coaching.relationships_between(from_at, to_at)
    |> Enum.map(fn relation ->
      %{
        coach_user_id: relation.coach_user_id,
        client_user_id: relation.client_user_id,
        from: ZonedTime.local_date(relation.started_at, zone),
        to: relation.ended_at && ZonedTime.local_date(relation.ended_at, zone)
      }
    end)
  end

  @impl true
  def staff_roles(context) do
    context
    |> Organizations.member_roles_by_user()
    |> Map.new(fn {user_id, member} ->
      {user_id, CoachPay.person_roles(member.roles, Map.get(member, :coach_scope))}
    end)
    |> Map.reject(fn {_user_id, roles} -> roles == [] end)
  end

  defp range(from, to, zone),
    do: {ZonedTime.start_of_day(from, zone), ZonedTime.start_of_day(Date.add(to, 1), zone)}

  defp zone(context), do: Organizations.organization_timezone(context.organization_id)
end

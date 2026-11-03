defmodule Palee.Infrastructure.Scheduling.EctoVisitFactsStore do
  @moduledoc "Postgres reads of earlier visits and referrals for visit badges (ADR-359)."

  @behaviour Palee.Scheduling.Ports.VisitFactsStore

  import Ecto.Query

  alias Palee.Facility.CheckIn
  alias Palee.Referrals.ReferralAttribution
  alias Palee.Repo
  alias Palee.Scheduling.{Booking, ClassAttendanceRecord, ScheduledClass}

  @impl true
  def visit_counts(_context, [], _before, _class_type_id, _exclude), do: %{}

  def visit_counts(%{organization_id: org}, user_ids, before, class_type_id, exclude) do
    exclude = exclude || []

    # A class counts when the person was marked attended, or when their seat
    # was approved and staff did not mark them missing.
    not_missed =
      from(r in ClassAttendanceRecord,
        where:
          r.scheduled_class_id == parent_as(:booking).scheduled_class_id and
            r.user_id == parent_as(:booking).user_id and r.status != "attended",
        select: 1
      )

    classes =
      from(b in Booking,
        as: :booking,
        join: c in ScheduledClass,
        on: c.id == b.scheduled_class_id,
        where:
          b.organization_id == ^org and b.user_id in ^user_ids and b.status == :approved and
            c.scheduled_at < ^before and c.id not in ^exclude and is_nil(c.cancelled_at) and
            (is_nil(b.guest_name) or b.guest_name == "") and not exists(not_missed),
        group_by: b.user_id,
        select:
          {b.user_id, count(c.id),
           count(c.id) |> filter(c.class_type_id == type(^class_type_id, :binary_id))}
      )
      |> Repo.all()
      |> Map.new(fn {user_id, total, typed} -> {user_id, {total, typed}} end)

    check_ins =
      from(ci in CheckIn,
        where:
          ci.organization_id == ^org and ci.user_id in ^user_ids and ci.checked_in_at < ^before,
        group_by: ci.user_id,
        select: {ci.user_id, count(ci.id)}
      )
      |> Repo.all()
      |> Map.new()

    Map.new(user_ids, fn user_id ->
      {total, typed} = Map.get(classes, user_id, {0, 0})

      {user_id,
       %{
         box_visits: total + Map.get(check_ins, user_id, 0),
         type_visits: if(class_type_id, do: typed)
       }}
    end)
  end

  @impl true
  def referrals(_context, []), do: %{}

  def referrals(%{organization_id: org}, user_ids) do
    from(r in ReferralAttribution,
      where: r.organization_id == ^org and r.referred_user_id in ^user_ids,
      order_by: [asc: r.referred_user_id, desc: r.attributed_at],
      distinct: r.referred_user_id,
      select: %{
        user_id: r.referred_user_id,
        channel: r.channel,
        referrer_user_id: r.referrer_user_id,
        event_id: r.community_event_id
      }
    )
    |> Repo.all()
    |> Map.new(&{&1.user_id, Map.delete(&1, :user_id)})
  end
end

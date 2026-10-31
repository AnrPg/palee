defmodule Palee.Application.GetCalendarFeed do
  alias Palee.Application.{CalendarFeedToken, Trials}
  alias Palee.{Community, Facility, Organizations, Scheduling}
  alias Palee.Scheduling.Domain.ICalendar
  alias Palee.Workouts.WorkoutStore
  alias Palee.Localization

  @past_days 30
  @future_days 365

  def call(token) do
    with {:ok, user} <- CalendarFeedToken.verify(token) do
      {:ok, build_feed(user)}
    end
  end

  defp build_feed(user) do
    locale = user.preferred_locale || "en"
    now = DateTime.utc_now()
    start_date = Date.utc_today() |> Date.add(-@past_days)
    end_date = Date.utc_today() |> Date.add(@future_days)
    start_at = DateTime.new!(start_date, ~T[00:00:00], "Etc/UTC")
    end_at = DateTime.new!(Date.add(end_date, 1), ~T[00:00:00], "Etc/UTC")

    # A personal calendar spans the gyms its owner attends (F-28), but each
    # gym's data must still be read under that gym's tenant context. Previously
    # this called the un-scoped arities, which resolve to the legacy
    # organization - so every user's feed carried the legacy gym's classes, and
    # a global admin's carried every athlete's assignments (F-18/F-29).
    contexts = active_tenant_contexts(user)

    events =
      Enum.flat_map(contexts, fn context ->
        class_events(context, user, start_at, end_at, locale) ++
          assignment_events(context, user, start_date, end_date, locale)
      end) ++
        trial_events(user, Enum.map(contexts, & &1.organization_id), locale) ++
        club_events(user, start_at, end_at, locale)

    render_ics(events, now)
  end

  defp active_tenant_contexts(user) do
    user.id
    |> Organizations.list_memberships()
    |> Enum.filter(&(&1.membership.status == :active))
    |> Enum.flat_map(fn %{organization: organization} ->
      case Organizations.resolve_tenant_context(user, organization.slug) do
        {:ok, context} -> [context]
        _unavailable -> []
      end
    end)
  end

  # Role comes from the membership in this organization, never the account.
  defp organization_admin?(context), do: context.role in [:owner, :admin, :coach]

  defp class_events(context, user, start_at, end_at, locale) do
    if context.role == :athlete do
      []
    else
      do_class_events(context, user, start_at, end_at, locale)
    end
  end

  defp do_class_events(context, user, start_at, end_at, locale) do
    slots =
      Scheduling.get_calendar_week(context, %{
        start_at: start_at,
        end_at: end_at,
        include_drafts: organization_admin?(context)
      })
      |> Enum.filter(&include_slot?(&1, user, organization_admin?(context)))

    locations = locations(context)

    if organization_admin?(context) do
      recurring_events =
        slots
        |> Enum.filter(& &1.class_series_id)
        |> Enum.group_by(& &1.class_series_id)
        |> Enum.map(fn {_series_id, [slot | _]} ->
          recurring_class_event(slot, user, locale, true)
        end)

      one_off_events =
        slots
        |> Enum.reject(& &1.class_series_id)
        |> Enum.map(&class_event(&1, user, locale, true))

      recurring_events ++ one_off_events
    else
      Enum.map(slots, &seat_event(&1, user, locale, locations))
    end
  end

  # ADR-359 (CP-E4): a seat keeps the class's UID for good; its status and
  # SEQUENCE follow the booking and the class, so a cancelled seat or class
  # stays in the window as CANCELLED and subscribed calendars drop it.
  @doc "One seat as a calendar event (also the single booking invite)."
  def seat_event(slot, user, locale, locations) do
    booking = own_booking(slot, user)
    status = ICalendar.status(booking && booking.status, slot.cancelled_at)

    slot
    |> class_event(user, locale, false)
    |> Map.merge(%{
      status: status,
      sequence:
        ICalendar.sequence([
          slot[:updated_at],
          slot.cancelled_at,
          booking && booking[:updated_at]
        ]),
      last_modified: latest([slot[:updated_at], booking && booking[:updated_at]]),
      location: Map.get(locations, slot.location_id),
      description:
        if(status == "CANCELLED",
          do: translate(locale, "This class or your booking was cancelled."),
          else: class_description(slot, user, locale, false)
        )
    })
  end

  @doc false
  def own_booking(slot, user) do
    (slot.bookings || [])
    |> Enum.filter(&(&1.user_id == user.id and blank?(Map.get(&1, :guest_name))))
    |> Enum.sort_by(&live_rank/1)
    |> List.first()
  end

  # A live seat beats an old cancelled one of the same class.
  defp live_rank(%{status: status}) when status in [:approved, :pending, :waitlisted], do: 0
  defp live_rank(_booking), do: 1

  defp blank?(value), do: value in [nil, ""]

  defp latest(moments) do
    moments
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&utc/1)
    |> Enum.max(DateTime, fn -> nil end)
  end

  defp utc(%DateTime{} = at), do: at
  defp utc(%NaiveDateTime{} = at), do: DateTime.from_naive!(at, "Etc/UTC")

  @doc false
  def locations(context) do
    context
    |> Facility.list_locations()
    |> case do
      list when is_list(list) -> Map.new(list, &{&1.id, location_text(&1)})
      _unavailable -> %{}
    end
  end

  defp location_text(location) do
    [Map.get(location, :name), Map.get(location, :address), Map.get(location, :city)]
    |> Enum.reject(&blank?/1)
    |> Enum.uniq()
    |> Enum.join(", ")
  end

  defp class_event(slot, user, locale, admin?) do
    %{
      uid: "class-#{slot.id}@palee",
      title: translate(locale, "Class: %{name}", %{name: class_name(slot)}),
      starts_at: slot.scheduled_at,
      ends_at: DateTime.add(slot.scheduled_at, slot.duration_minutes * 60, :second),
      description: class_description(slot, user, locale, admin?)
    }
  end

  defp recurring_class_event(slot, user, locale, admin?) do
    series = slot.class_series

    %{
      uid: "class-series-#{series.id}@palee",
      title: translate(locale, "Class: %{name}", %{name: series.name}),
      recurrence: series,
      starts_at: slot.scheduled_at,
      duration_minutes: series.duration_minutes,
      description: class_description(slot, user, locale, admin?)
    }
  end

  # ADR-144 (board 6 Q5): trials at boxes the person isn't a member of; at
  # their own gym the trial seat already shows as a class booking.
  defp trial_events(user, member_organization_ids, locale) do
    user
    |> Trials.mine()
    |> Enum.filter(&(&1.status in ~w(requested booked)))
    |> Enum.reject(&(&1.organization_id in member_organization_ids))
    |> Enum.map(fn trial ->
      starts_at = trial.class.scheduled_at
      minutes = trial.class[:duration_minutes] || 60

      %{
        uid: "trial-#{trial.id}@palee",
        title:
          translate(locale, "Trial at %{box}: %{name}", %{
            box: (trial.box && trial.box.name) || "",
            name: trial.class.name || ""
          }),
        starts_at: starts_at,
        ends_at: DateTime.add(starts_at, minutes * 60, :second),
        description:
          translate(locale, "Trial status: %{status}.", %{
            status: translate(locale, trial_status_message(trial.status))
          })
      }
    end)
  end

  # ADR-153: club events the person is going to, at any box.
  defp club_events(user, start_at, end_at, locale) do
    %{user_id: user.id}
    |> Community.attendances_of(user.id, ["going"])
    |> Enum.group_by(& &1.organization_id, & &1.event_id)
    |> Enum.flat_map(fn {organization_id, ids} ->
      Community.list_events(%{organization_id: organization_id, user_id: user.id}, %{
        organization_ids: [organization_id],
        ids: ids,
        from: start_at,
        to: end_at
      })
    end)
    |> Enum.map(fn event ->
      %{
        uid: "community-event-#{event.id}@palee",
        title: translate(locale, "Event: %{title}", %{title: event.title}),
        starts_at: event.starts_at,
        ends_at: event.ends_at,
        description: translate(locale, "You're going to this event.")
      }
    end)
  end

  defp trial_status_message("requested"), do: "Waiting for the box"
  defp trial_status_message(_booked), do: "Booked"

  defp assignment_events(context, user, start_date, end_date, locale) do
    cond do
      context.role == :member ->
        []

      organization_admin?(context) ->
        WorkoutStore.list_assigned_workouts_for_admin(context, start_date, end_date)
        |> Enum.map(&assignment_event(&1, locale))

      true ->
        WorkoutStore.list_assigned_workouts_for_athlete(context, user.id, start_date, end_date)
        |> Enum.map(&assignment_event(&1, locale))
    end
  end

  defp assignment_event(assignment, locale) do
    scheduled_for = date_value(assignment.scheduled_for)

    title =
      assignment
      |> get_in([:workout, :title])
      |> case do
        nil -> translate(locale, "Assigned workout")
        "" -> translate(locale, "Assigned workout")
        value -> translate(locale, "Workout: %{title}", %{title: value})
      end

    %{
      uid: "assigned-workout-#{assignment.id}@palee",
      title: title,
      starts_on: scheduled_for,
      ends_on: Date.add(scheduled_for, 1),
      description: translate(locale, "Assigned workout in Palee.")
    }
  end

  defp date_value(%Date{} = date), do: date
  defp date_value(value) when is_binary(value), do: Date.from_iso8601!(value)

  defp include_slot?(_slot, _user, true = _admin?), do: true

  # ADR-359: every seat of the person in the window, cancelled ones too
  # (as CANCELLED), so a subscribed calendar removes them.
  defp include_slot?(slot, user, _admin?) do
    Enum.any?(slot.bookings || [], fn booking ->
      booking.user_id == user.id and
        booking.status in [:pending, :approved, :waitlisted, :cancelled, :rejected]
    end)
  end

  defp class_description(slot, _user, locale, true = _admin?) do
    translate(locale, "Scheduled %{name} class in Palee.", %{name: class_name(slot)})
  end

  defp class_description(slot, user, locale, _admin?) do
    booking =
      Enum.find(slot.bookings || [], fn booking ->
        booking.user_id == user.id and booking.status in [:pending, :approved, :waitlisted]
      end)

    status = if booking, do: booking.status, else: "scheduled"
    localized_status = translate(locale, status_message(status))

    translate(locale, "Palee class booking status: %{status}.", %{
      status: localized_status
    })
  end

  defp render_ics(events, now), do: ICalendar.render(events, now)

  defp class_type_name(%{class_type: %{name: name}}) when is_binary(name), do: name
  defp class_type_name(_slot), do: "—"

  defp class_name(%{name: name}) when is_binary(name) and name != "Class", do: name
  defp class_name(slot), do: class_type_name(slot)

  defp status_message(:pending), do: "Pending"
  defp status_message(:approved), do: "Approved"
  defp status_message(:waitlisted), do: "Waitlisted"
  defp status_message("scheduled"), do: "Scheduled"
  defp status_message(status), do: to_string(status)

  defp translate(locale, message, bindings \\ %{}),
    do: Localization.translate(locale, message, bindings, "calendar")
end

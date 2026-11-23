defmodule Palee.Application.BoxScreens.ClassScreens do
  @moduledoc """
  «Στην οθόνη» on a class timer's remote (ADR-253, update 2026-10-29): the
  coach running a class pins its timer, leaderboard or WOD on a box screen
  and returns the screen to automatic, without the settings page.

  Who may is `BoxScreens.Domain.ClassScreenPolicy`: the class's own coach,
  today, on a screen of the class's branch or the whole box; staff who
  manage screens (`manage_settings` or `manage_locations`) as on Staff ›
  Box screens. A coach of another class is refused. The pin always names
  the class (`slot_id`), so it ends with the class's day.

  ADR-746 (ANR picks 7A, 8A): each screen comes with what it shows now (its
  class, coach and whether a timer runs there), so the remote asks before
  replacing a running timer. A pin may name one of the class's WODs (nil
  follows its «Τώρα») and share the screen with a class that runs at the
  same time. A coach of today's class may take a screen another coach's
  class holds; that coach hears about it and can take it back.
  """

  alias Palee.{BoxScreens, Execution, Notifications, Organizations, Scheduling, Workouts}
  alias Palee.Scheduling.Domain.ClassWorkouts
  alias Palee.Application.BoxScreens.{BoxScreenToday, ScreenPresenter}
  alias Palee.TimeZones.ZonedTime

  @doc """
  The screens the person may change for class `slot_id`, with what each
  shows: `{:ok, %{screens, views}}`, or `{:error, :forbidden | :not_found}`.
  """
  def list(context, slot_id) do
    now = BoxScreens.now()

    with {:ok, class, today} <- load(context, slot_id, now) do
      actor = actor(context)

      extras = %{
        views: BoxScreens.class_views(actor),
        workouts: workouts(context, class.slot),
        together: together(context, class)
      }

      case BoxScreens.class_screens(actor, class, BoxScreens.list(context), today) do
        [] ->
          if allowed?(actor, class, today),
            do: {:ok, Map.put(extras, :screens, [])},
            else: {:error, :forbidden}

        screens ->
          names = ScreenPresenter.names(Enum.map(screens, & &1.focus_changed_by_id))

          {:ok,
           Map.put(
             extras,
             :screens,
             Enum.map(screens, fn screen ->
               screen
               |> ScreenPresenter.view(names, now)
               |> Map.put(:showing, showing(context, screen, now))
             end)
           )}
      end
    end
  end

  @doc "Pins `view` of class `slot_id` on screen `screen_id` (optionally `until`)."
  def pin(context, slot_id, screen_id, params) do
    now = BoxScreens.now()
    view = param(params, :view)

    with {:ok, class, today} <- load(context, slot_id, now),
         {:ok, screen} <- screen(context, screen_id),
         :ok <- BoxScreens.may_pin_class?(actor(context), class, screen, view, today),
         {:ok, workout_id} <- class_workout(class.slot, param(params, :workout_id)),
         {:ok, split_slot_id} <- split_with(context, class, param(params, :split_slot_id)),
         previous = BoxScreens.active_override(screen, now),
         {:ok, pinned} <-
           BoxScreens.set_override(
             context,
             screen.id,
             %{
               view: view,
               slot_id: class.id,
               until: param(params, :until),
               workout_id: workout_id,
               split_slot_id: split_slot_id
             },
             BoxScreenToday.slot_ids(context, screen, now),
             context.user_id,
             now
           ) do
      ScreenPresenter.announce(context, pinned, now)
      notify_taken(context, screen, previous, class, now)
      {:ok, %{screen: ScreenPresenter.view(pinned, now)}}
    end
  end

  # ADR-746: one of the class's WODs, or nil for its «Τώρα».
  defp class_workout(_slot, blank) when blank in [nil, ""], do: {:ok, nil}

  defp class_workout(slot, workout_id) do
    if ClassWorkouts.member?(slot, workout_id),
      do: {:ok, workout_id},
      else: {:error, :not_a_class_workout}
  end

  # ADR-746: a class that runs at the same time as this one.
  defp split_with(_context, _class, blank) when blank in [nil, ""], do: {:ok, nil}

  defp split_with(context, class, slot_id) do
    if Enum.any?(together(context, class), &(&1.id == slot_id)),
      do: {:ok, slot_id},
      else: {:error, :invalid_screen_override}
  end

  # The class's WODs in order, «Τώρα» marked.
  defp workouts(context, slot) do
    live = ClassWorkouts.live_id(slot)

    Enum.map(ClassWorkouts.ids(slot), fn id ->
      workout = Workouts.get_workout(context, id)
      %{id: id, title: workout && workout.title, live: id == live}
    end)
  end

  # The other classes of the same branch (or the whole box) that overlap
  # this one, not cancelled.
  defp together(context, class) do
    slot = class.slot
    ends = BoxScreens.ends_at(slot)

    others =
      context
      |> Scheduling.get_calendar_week(%{
        start_at: DateTime.add(slot.scheduled_at, -86_400),
        end_at: ends
      })
      |> List.wrap()
      |> Enum.filter(&overlaps?(&1, slot, ends))

    names = ScreenPresenter.names(Enum.map(others, & &1.coach_user_id))

    Enum.map(others, fn other ->
      %{id: other.id, name: class_name(other), coach_name: Map.get(names, other.coach_user_id)}
    end)
  end

  defp overlaps?(other, slot, ends) do
    other.id != slot.id and is_nil(other.cancelled_at) and
      (is_nil(slot.location_id) or other.location_id in [nil, slot.location_id]) and
      DateTime.compare(other.scheduled_at, ends) == :lt and
      DateTime.compare(BoxScreens.ends_at(other), slot.scheduled_at) == :gt
  end

  defp class_name(slot), do: slot.name || (slot.class_type && slot.class_type.name)

  # What the screen shows now: its class and whether a timer runs there.
  defp showing(context, screen, now) do
    {focus, classes} = BoxScreenToday.focus(context, screen, now)
    slot = focus.slot_id && Enum.find(classes, &(&1.id == focus.slot_id))

    %{
      slot_id: focus.slot_id,
      view: focus.view,
      class_name: slot && class_name(slot),
      coach_name: slot && coach_name(slot.coach_user_id),
      timer_running:
        focus.view == "timer" and is_binary(focus.slot_id) and running?(context, focus.slot_id)
    }
  end

  defp coach_name(nil), do: nil
  defp coach_name(id), do: id |> List.wrap() |> ScreenPresenter.names() |> Map.get(id)

  defp running?(context, slot_id),
    do: context |> Execution.list_class_timers(slot_id) |> Enum.any?(&(&1.status == "running"))

  # ADR-746: whoever pinned the screen for another class hears it was taken.
  defp notify_taken(_context, _screen, nil, _class, _now), do: :ok

  defp notify_taken(context, screen, %{slot_id: previous_slot}, class, now) do
    owner = screen.focus_changed_by_id

    if is_binary(owner) and owner != context.user_id and previous_slot != class.id do
      Notifications.dispatch_event(:box_screen_taken, %{
        organization_id: context.organization_id,
        user_id: owner,
        screen_id: screen.id,
        screen_name: screen.name,
        taken_by: coach_name(context.user_id),
        slot_id: previous_slot,
        taken_at: DateTime.to_unix(now),
        url: previous_slot && "/class-timer/#{previous_slot}/control"
      })
    end

    :ok
  end

  @doc "«Επιστροφή στο αυτόματο» from class `slot_id`'s remote."
  def unpin(context, slot_id, screen_id) do
    now = BoxScreens.now()

    with {:ok, class, today} <- load(context, slot_id, now),
         {:ok, screen} <- screen(context, screen_id),
         :ok <-
           BoxScreens.may_clear_class?(
             actor(context),
             class,
             screen,
             BoxScreens.active_override(screen, now),
             today
           ),
         {:ok, screen} <- BoxScreens.clear_override(context, screen.id, context.user_id, now) do
      ScreenPresenter.announce(context, screen, now)
      {:ok, %{screen: ScreenPresenter.view(screen, now)}}
    end
  end

  # A coach without a screen to choose still gets an empty list; anyone
  # else is refused.
  defp allowed?(%{manages_screens: true}, _class, _today), do: true

  defp allowed?(actor, class, today),
    do: BoxScreens.coaches_class_today?(actor, class, today)

  defp actor(context) do
    %{
      user_id: context.user_id,
      manages_screens:
        Organizations.can?(context, :manage_settings) or
          Organizations.can?(context, :manage_locations),
      scope: Organizations.location_scope(context)
    }
  end

  defp load(context, slot_id, now) do
    with {:ok, slot_id} <- Ecto.UUID.cast(slot_id),
         %{} = slot <- Scheduling.get_slot(context, slot_id) do
      zone = Organizations.organization_timezone(context.organization_id)

      {:ok,
       %{
         id: slot.id,
         coach_user_id: slot.coach_user_id,
         location_id: slot.location_id,
         cancelled_at: slot.cancelled_at,
         date: ZonedTime.local_date(slot.scheduled_at, zone),
         slot: slot
       }, ZonedTime.local_date(now, zone)}
    else
      _missing -> {:error, :not_found}
    end
  end

  defp screen(context, id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %{} = screen <- BoxScreens.get(context, id) do
      {:ok, screen}
    else
      _missing -> {:error, :box_screen_not_found}
    end
  end

  defp param(params, key), do: Map.get(params, key, Map.get(params, Atom.to_string(key)))
end

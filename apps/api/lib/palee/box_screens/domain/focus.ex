defmodule Palee.BoxScreens.Domain.Focus do
  @moduledoc """
  What a box screen puts first right now (ADR-253), pure.

  Automatically (`source: "auto"`), from today's classes on the box's clock:

    * `timer` – a class is running (start ≤ now < end): its class timer;
    * `results` – a class ended less than #{30} minutes ago and none is
      running: its WOD's leaderboard;
    * `preview` – the next class of the day: its WOD and bookings;
    * `idle` – nothing left today.

  A running class wins over results, the latest-starting running class over
  an earlier one; cancelled classes are skipped.

  Staff can pin something else (`source: "staff"`, ADR-253): `wod`, `timer`,
  `leaderboard`, `bookings` or `class`, optionally for one class and until
  a time. An override for a class no longer on today's screen falls back to
  automatic.

  ADR-746 (ANR pick 8A): a screen may follow one room of its branch
  (`space_id`): in automatic it puts that room's class first and falls back
  to the rest of the day only when the room has none. When classes run
  together, `concurrent_mode` `room` (the default) keeps to one class, `split`
  shows two side by side (`split_slot_id`). A pin may name the WOD it shows
  (`workout_id`, nil = the class's «Τώρα») and share the screen this once.
  """

  @results_minutes 30

  def results_minutes, do: @results_minutes

  @doc """
  `%{source, view, slot_id, until}` for `classes`
  (`%{id, scheduled_at, duration_minutes, cancelled}`) at `now`, honouring
  `override` (`%{view, slot_id, until}` or nil). `screen` may carry
  `space_id` and `concurrent_mode` (ADR-746).
  """
  def resolve(classes, override, %DateTime{} = now, screen \\ %{}) do
    case staff(override, classes) do
      nil -> auto(classes, now, screen)
      focus -> focus
    end
  end

  defp staff(nil, _classes), do: nil

  defp staff(%{slot_id: nil} = override, _classes), do: pinned(override, nil, nil)

  defp staff(%{slot_id: slot_id} = override, classes) do
    if Enum.any?(classes, &(&1.id == slot_id)) do
      split = Map.get(override, :split_slot_id)
      pinned(override, slot_id, if(Enum.any?(classes, &(&1.id == split)), do: split))
    end
  end

  defp pinned(override, slot_id, split) do
    %{
      source: "staff",
      view: override.view,
      slot_id: slot_id,
      until: override.until,
      workout_id: if(slot_id, do: Map.get(override, :workout_id)),
      split_slot_id: split
    }
  end

  @doc "The automatic focus alone."
  def auto(classes, %DateTime{} = now, screen \\ %{}) do
    live = classes |> Enum.reject(& &1.cancelled) |> Enum.sort_by(& &1.scheduled_at, DateTime)
    running_now = Enum.filter(live, &(started?(&1, now) and not ended?(&1, now)))

    case {Map.get(screen, :concurrent_mode), running_now} do
      {"split", [_, _ | _]} ->
        [first, second] = Enum.take(running_now, -2)
        %{focus("timer", first) | split_slot_id: second.id}

      _one_or_room ->
        auto_one(in_room(live, Map.get(screen, :space_id)), now)
    end
  end

  # The screen's room first; the rest of the day only when it has nothing.
  defp in_room(classes, nil), do: classes

  defp in_room(classes, space_id) do
    case Enum.filter(classes, &(Map.get(&1, :space_id) == space_id)) do
      [] -> classes
      own -> own
    end
  end

  defp auto_one(live, now) do
    running =
      live
      |> Enum.filter(&(started?(&1, now) and not ended?(&1, now)))
      |> List.last()

    recent =
      live
      |> Enum.filter(&(ended?(&1, now) and within_results?(&1, now)))
      |> List.last()

    next = Enum.find(live, &(not started?(&1, now)))

    cond do
      running ->
        focus("timer", running)

      recent ->
        focus("results", recent)

      next ->
        focus("preview", next)

      true ->
        %{
          source: "auto",
          view: "idle",
          slot_id: nil,
          until: nil,
          workout_id: nil,
          split_slot_id: nil
        }
    end
  end

  defp focus(view, class),
    do: %{
      source: "auto",
      view: view,
      slot_id: class.id,
      until: nil,
      workout_id: nil,
      split_slot_id: nil
    }

  @doc "When a class ends."
  def ends_at(%{scheduled_at: at, duration_minutes: minutes}),
    do: DateTime.add(at, (minutes || 60) * 60, :second)

  defp started?(class, now), do: DateTime.compare(class.scheduled_at, now) != :gt
  defp ended?(class, now), do: DateTime.compare(ends_at(class), now) != :gt

  defp within_results?(class, now),
    do: DateTime.diff(now, ends_at(class), :second) < @results_minutes * 60
end

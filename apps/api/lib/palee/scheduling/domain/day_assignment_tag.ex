defmodule Palee.Scheduling.Domain.DayAssignmentTag do
  @moduledoc """
  ADR-357 (CP-D3): the tag a programming calendar shows on a gym day.

    * `none` – no classes (nothing to tag);
    * `not_assigned` – classes, none with a WOD («Χωρίς WOD»);
    * `mixed` – some classes with a WOD and some without («Μικτό»);
    * `all_assigned` – every class has its WOD («Όλα με WOD»).

  Cancelled classes do not count: they need no WOD. A class counts as
  having a WOD when it links one (`master_workout_id`), whether its own or
  the day's (ADR-230).
  """

  @tags ~w(none not_assigned mixed all_assigned)

  def tags, do: @tags

  @doc "The tag of one day's classes, with the counts it was read from."
  @spec tag([map()]) :: %{
          tag: String.t(),
          classes: non_neg_integer(),
          with_wod: non_neg_integer()
        }
  def tag(classes) when is_list(classes) do
    live = Enum.reject(classes, &Map.get(&1, :cancelled_at))
    with_wod = Enum.count(live, &Map.get(&1, :master_workout_id))
    total = length(live)

    %{tag: name(total, with_wod), classes: total, with_wod: with_wod}
  end

  @doc """
  One entry per date of `dates`, in order: `%{date, tag, classes, with_wod}`.
  `classes` carry `local_date` (the gym day).
  """
  @spec by_day([Date.t()], [map()]) :: [map()]
  def by_day(dates, classes) do
    grouped = Enum.group_by(classes, & &1.local_date)

    Enum.map(dates, fn date ->
      grouped |> Map.get(date, []) |> tag() |> Map.put(:date, date)
    end)
  end

  defp name(0, _with_wod), do: "none"
  defp name(_total, 0), do: "not_assigned"
  defp name(total, total), do: "all_assigned"
  defp name(_total, _with_wod), do: "mixed"
end

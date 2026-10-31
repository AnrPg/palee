defmodule Palee.Execution.Domain.Pacer do
  @moduledoc """
  «Ο προηγούμενος εαυτός σου» (ADR-374, CP-D7): the person's previous
  attempt at the same WOD or benchmark runs beside the timer as a pace line
  (a "ghost"), split by section and round, and the results compare the two.
  Comparison is only ever with the person themself (vision §4.4).

  Which attempt: the newest completed execution with the same workout
  identity (`WorkoutIdentity`: same benchmark, same library workout, or
  same name and kind) that finished before this one started, preferring
  one at the same scale level.

  How precise: `rounds` when the previous attempt has round marks,
  `segments` when it has segment marks only, `sections` when it only has
  the time spent per section (executions from before ADR-374), `finish`
  when it only has a total.

  Checkpoints match by key `"<section ordinal>:<phase>:<round>:<n>"`, where
  `n` counts repeats of the same section, phase and round in time order.
  """

  @type checkpoint :: %{
          key: String.t(),
          section_ordinal: non_neg_integer(),
          phase: String.t(),
          round: non_neg_integer(),
          at_ms: non_neg_integer(),
          lap_ms: non_neg_integer()
        }

  @doc """
  The attempt to race: `candidates` are `%{id, key, status, completed_at_utc,
  scale_level_slug}`; `current` has `id`, `key`, `started_at_utc` and
  `scale_level_slug`. Nil when there is none.
  """
  def pick_previous(_candidates, %{key: nil}), do: nil

  def pick_previous(candidates, current) do
    candidates
    |> Enum.filter(fn candidate ->
      candidate.id != current.id and candidate.key == current.key and
        to_string(candidate.status) == "completed" and
        match?(%DateTime{}, candidate.completed_at_utc) and
        DateTime.compare(candidate.completed_at_utc, current.started_at_utc) != :gt
    end)
    |> Enum.sort_by(
      &{if(&1.scale_level_slug == current.scale_level_slug, do: 1, else: 0),
        DateTime.to_unix(&1.completed_at_utc, :microsecond)},
      :desc
    )
    |> List.first()
  end

  @doc "Checkpoints from stored split marks, in time order."
  @spec checkpoints([map()]) :: [checkpoint()]
  def checkpoints(splits) do
    splits
    |> Enum.sort_by(&{&1.elapsed_ms, &1.segment_index, &1.round})
    |> Enum.map_reduce({0, %{}}, fn split, {previous_at, seen} ->
      base = {split.section_ordinal, split.phase, split.round}
      n = Map.get(seen, base, 0)

      checkpoint = %{
        key: "#{split.section_ordinal}:#{split.phase}:#{split.round}:#{n}",
        section_ordinal: split.section_ordinal,
        phase: split.phase,
        round: split.round,
        at_ms: split.elapsed_ms,
        lap_ms: max(split.elapsed_ms - previous_at, 0)
      }

      {checkpoint, {split.elapsed_ms, Map.put(seen, base, n + 1)}}
    end)
    |> elem(0)
  end

  @doc """
  Time per section ordinal: from an execution's `section_elapsed_ms` read
  through its own segments' ordinals (section id → ordinal).
  """
  def section_times(section_elapsed_ms, ordinals) when is_map(section_elapsed_ms) do
    Enum.reduce(section_elapsed_ms, %{}, fn {section_id, ms}, acc ->
      base = Palee.Execution.Domain.SplitMarks.base_section_id(to_string(section_id))

      case Map.fetch(ordinals, base) do
        {:ok, ordinal} when is_integer(ms) -> Map.update(acc, ordinal, ms, &(&1 + ms))
        _unknown -> acc
      end
    end)
  end

  def section_times(_section_elapsed_ms, _ordinals), do: %{}

  @doc "How precise the pace line is."
  def precision(checkpoints, section_times) do
    cond do
      Enum.any?(checkpoints, &(&1.round > 0 and &1.phase == "work")) -> "rounds"
      checkpoints != [] -> "segments"
      map_size(section_times) > 0 -> "sections"
      true -> "finish"
    end
  end

  @doc """
  The pace line against the current attempt. `ghost` and `current` are
  `%{checkpoints, section_times, total_ms}`; `names` maps a section ordinal
  to the current plan's `%{section_id, section_name}`.

  `delta_ms` is current minus previous: negative is ahead of the previous
  attempt, positive behind; nil until the current attempt reaches it.
  """
  def compare(ghost, current, names) do
    current_at = Map.new(current.checkpoints, &{&1.key, &1})

    %{
      precision: precision(ghost.checkpoints, ghost.section_times),
      checkpoints:
        Enum.map(ghost.checkpoints, fn checkpoint ->
          mine = Map.get(current_at, checkpoint.key)

          checkpoint
          |> Map.take([:key, :section_ordinal, :phase, :round])
          |> Map.merge(section_name(names, checkpoint.section_ordinal))
          |> Map.merge(%{
            ghost_at_ms: checkpoint.at_ms,
            ghost_lap_ms: checkpoint.lap_ms,
            at_ms: mine && mine.at_ms,
            lap_ms: mine && mine.lap_ms,
            delta_ms: mine && mine.at_ms - checkpoint.at_ms
          })
        end),
      sections:
        ghost.section_times
        |> Enum.sort()
        |> Enum.map(fn {ordinal, ghost_ms} ->
          mine = Map.get(current.section_times, ordinal)

          names
          |> section_name(ordinal)
          |> Map.merge(%{
            section_ordinal: ordinal,
            ghost_ms: ghost_ms,
            current_ms: mine,
            delta_ms: mine && mine - ghost_ms
          })
        end),
      ghost_total_ms: ghost.total_ms,
      current_total_ms: current.total_ms,
      total_delta_ms: total_delta(ghost.total_ms, current.total_ms, current.completed?)
    }
  end

  defp total_delta(ghost, current, true) when is_integer(ghost) and is_integer(current),
    do: current - ghost

  defp total_delta(_ghost, _current, _completed?), do: nil

  defp section_name(names, ordinal),
    do: Map.get(names, ordinal, %{section_id: nil, section_name: nil})

  @doc "Ordinal → `%{section_id, section_name}` of a plan's real sections."
  def section_names(segments) do
    segments
    |> Enum.map(fn segment ->
      id = segment |> value(:section_id) |> to_string()
      {Palee.Execution.Domain.SplitMarks.base_section_id(id), value(segment, :section_name)}
    end)
    |> Enum.uniq_by(&elem(&1, 0))
    |> Enum.with_index()
    |> Map.new(fn {{id, name}, ordinal} -> {ordinal, %{section_id: id, section_name: name}} end)
  end

  defp value(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
end

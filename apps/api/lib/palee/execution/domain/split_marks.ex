defmodule Palee.Execution.Domain.SplitMarks do
  @moduledoc """
  Split marks sent while a WOD runs (ADR-374, CP-D7), checked against the
  execution's own timer segments. A mark is `%{segment_index, round,
  elapsed_ms}`:

    * `round` absent or 0 – the segment ended;
    * `round` ≥ 1 – the athlete finished that round inside the segment (an
      AMRAP's round taps), or the segment's own round (EMOM, intervals).

  Each mark is placed in its section: `section_ordinal` counts the real
  sections in timer order (transitions between sections share their
  section's ordinal), so two attempts at copies of the same benchmark line
  up even when their section ids differ.

  Marks arrive in batches from the phone or a watch that may have been
  offline, so they may repeat or come out of order: the store ignores a
  mark it already has (same segment and round).
  """

  @max_marks 500
  @max_elapsed_ms 2_592_000_000
  @max_round 1_000_000

  def max_marks, do: @max_marks

  @doc "`{:ok, rows}` ready to store, or `{:error, :invalid_split_marks}`."
  def cast(marks, segments) when is_list(marks) and is_list(segments) do
    ordinals = section_ordinals(segments)

    indexed =
      segments |> Enum.with_index() |> Map.new(fn {segment, index} -> {index, segment} end)

    if marks != [] and length(marks) <= @max_marks do
      marks
      |> Enum.reduce_while({:ok, []}, fn mark, {:ok, rows} ->
        case cast_mark(mark, indexed, ordinals) do
          {:ok, row} -> {:cont, {:ok, [row | rows]}}
          :error -> {:halt, {:error, :invalid_split_marks}}
        end
      end)
      |> case do
        {:ok, rows} ->
          {:ok, rows |> Enum.reverse() |> Enum.uniq_by(&{&1.segment_index, &1.round})}

        error ->
          error
      end
    else
      {:error, :invalid_split_marks}
    end
  end

  def cast(_marks, _segments), do: {:error, :invalid_split_marks}

  @doc """
  The marks a progress update implies, so a timer that only saves its
  progress still leaves a pace line (ADR-374 amendment 2026-11-03):

    * every segment the update moved past ended (`round` 0);
    * every new count of a segment's rounds (`segment_cycle_counts`, the
      AMRAP «Γύρος» taps) finished that round.

  Each takes the update's `total_elapsed_ms`, except a round the device
  timed itself (`device_marks`, the progress payload's `round_marks`). Marks the segments do not
  allow are dropped, never an error: progress must save regardless. Marks
  the timer or a watch sent itself win, because the store keeps the first
  mark of a segment and round.
  """
  def from_progress(previous, updated, segments, device_marks \\ [])

  def from_progress(previous, updated, segments, device_marks) when is_list(segments) do
    elapsed = get(updated, :total_elapsed_ms)

    if is_integer(elapsed) and segments != [] do
      ended = ended_segments(get(previous, :current_segment_index), updated, segments)
      rounds = finished_rounds(previous, updated, segments)
      exact = device_times(device_marks, segments, elapsed)

      (ended ++ rounds)
      |> Enum.map(
        &Map.put(&1, :elapsed_ms, Map.get(exact, {&1.segment_index, &1.round}, elapsed))
      )
      |> Enum.flat_map(fn mark ->
        case cast([mark], segments) do
          {:ok, rows} -> rows
          {:error, _invalid} -> []
        end
      end)
      |> Enum.uniq_by(&{&1.segment_index, &1.round})
      |> Enum.take(@max_marks)
    else
      []
    end
  end

  def from_progress(_previous, _updated, _segments, _device_marks), do: []

  # ADR-549: the times the device itself saw for its round taps
  # (`round_marks`: `%{segment_key, round, elapsed_ms}`, active ms since the
  # start), so rounds saved together keep their own times. A time after the
  # update's own elapsed time is not believed.
  defp device_times(marks, segments, elapsed) when is_list(marks) do
    index_by_key =
      segments
      |> Enum.with_index()
      |> Map.new(fn {segment, index} -> {to_string(get(segment, :segment_key)), index} end)

    marks
    |> Enum.take(@max_marks)
    |> Enum.flat_map(fn mark ->
      with %{} <- mark,
           index when is_integer(index) <-
             Map.get(index_by_key, to_string(get(mark, :segment_key))),
           round when is_integer(round) and round >= 1 <- get(mark, :round),
           ms when is_integer(ms) and ms >= 0 and ms <= elapsed <- get(mark, :elapsed_ms) do
        [{{index, round}, ms}]
      else
        _invalid -> []
      end
    end)
    |> Map.new()
  end

  defp device_times(_marks, _segments, _elapsed), do: %{}

  defp ended_segments(from, updated, segments) do
    to = get(updated, :current_segment_index)
    last = length(segments) - 1

    finished? =
      to_string(get(updated, :status)) == "completed" and is_integer(to) and to == last

    to = if finished?, do: to + 1, else: to

    if is_integer(from) and is_integer(to) and to > from,
      do: for(index <- from..(to - 1)//1, do: %{segment_index: index, round: 0}),
      else: []
  end

  defp finished_rounds(previous, updated, segments) do
    before = get(previous, :segment_cycle_counts) || %{}
    now = get(updated, :segment_cycle_counts) || %{}

    index_by_key =
      segments
      |> Enum.with_index()
      |> Map.new(fn {segment, index} -> {to_string(get(segment, :segment_key)), index} end)

    Enum.flat_map(now, fn {key, count} ->
      old = Map.get(before, key, Map.get(before, to_string(key), 0))

      with index when is_integer(index) <- Map.get(index_by_key, to_string(key)),
           true <- is_integer(count) and is_integer(old) and count > old do
        for round <- max(old + 1, count - @max_marks + 1)..count//1,
            do: %{segment_index: index, round: round}
      else
        _none -> []
      end
    end)
  end

  defp cast_mark(mark, segments, ordinals) when is_map(mark) do
    index = get(mark, :segment_index)
    round = get(mark, :round) || 0
    elapsed = get(mark, :elapsed_ms)

    with true <- is_integer(index),
         %{} = segment <- Map.get(segments, index),
         true <- is_integer(round) and round >= 0 and round <= @max_round,
         true <- round_allowed?(segment, round),
         true <- is_integer(elapsed) and elapsed >= 0 and elapsed <= @max_elapsed_ms do
      section_id = segment |> get(:section_id) |> to_string()

      {:ok,
       %{
         segment_index: index,
         section_id: String.slice(section_id, 0, 120),
         section_ordinal: Map.fetch!(ordinals, base_section_id(section_id)),
         phase: phase(segment),
         round: if(round == 0, do: get(segment, :round) || 0, else: round),
         elapsed_ms: elapsed
       }}
    else
      _invalid -> :error
    end
  end

  defp cast_mark(_mark, _segments, _ordinals), do: :error

  # A fixed-round segment only takes its own rounds; open-ended ones any.
  defp round_allowed?(_segment, 0), do: true

  defp round_allowed?(segment, round) do
    case {get(segment, :kind), get(segment, :total_rounds)} do
      {kind, _total} when kind in [:interval_cycle, "interval_cycle"] -> true
      {_kind, total} when is_integer(total) and total > 0 -> round <= total
      _other -> true
    end
  end

  defp phase(segment) do
    case to_string(get(segment, :phase) || "work") do
      phase when phase in ~w(work rest transition) -> phase
      _other -> "work"
    end
  end

  @doc "Section id → ordinal (0-based) of the real sections, in timer order."
  def section_ordinals(segments) do
    segments
    |> Enum.map(&(&1 |> get(:section_id) |> to_string() |> base_section_id()))
    |> Enum.uniq()
    |> Enum.with_index()
    |> Map.new()
  end

  @doc "The section a between-sections segment belongs to."
  def base_section_id(section_id) do
    section_id
    |> String.replace_suffix(":transition", "")
    |> String.replace_suffix(":rest-after", "")
  end

  defp get(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
end

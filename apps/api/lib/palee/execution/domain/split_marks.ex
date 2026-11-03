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

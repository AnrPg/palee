defmodule Palee.Devices.Domain.HeartRate do
  @moduledoc """
  Heart rate from a watch during an execution (ADR-375). Health data: kept
  only with the person's `health_data` consent, visible only to them.

  Batches: `%{sequence, started_offset_ms, interval_ms, bpm: [..]}`, at most
  30 per request and 720 samples each (an hour at 5 s); samples outside
  25–250 bpm are sensor noise and become `nil` gaps (never stored as such:
  a batch keeps its numbers, the summary skips them).

  The summary is what the results show: average, highest and lowest,
  average per section (by the section times of the execution) and, when
  the person told the watch their maximum heart rate, the time in each of
  the five zones (50–60 %, 60–70 %, 70–80 %, 80–90 %, 90–100 %).
  """

  @max_batches 30
  @max_samples 720
  @min_bpm 25
  @max_bpm 250
  @zones [{1, 0.5, 0.6}, {2, 0.6, 0.7}, {3, 0.7, 0.8}, {4, 0.8, 0.9}, {5, 0.9, 10.0}]

  def max_batches, do: @max_batches

  @doc "`{:ok, rows}` or `{:error, :invalid_heart_rate_batch}`."
  def cast_batches(batches, platform) when is_list(batches) and batches != [] do
    if length(batches) <= @max_batches and
         platform in Palee.Devices.Domain.WatchContract.platforms() do
      batches
      |> Enum.reduce_while({:ok, []}, fn batch, {:ok, rows} ->
        case cast_batch(batch) do
          {:ok, row} -> {:cont, {:ok, [Map.put(row, :platform, platform) | rows]}}
          :error -> {:halt, {:error, :invalid_heart_rate_batch}}
        end
      end)
      |> case do
        {:ok, rows} -> {:ok, rows |> Enum.reverse() |> Enum.uniq_by(& &1.sequence)}
        error -> error
      end
    else
      {:error, :invalid_heart_rate_batch}
    end
  end

  def cast_batches(_batches, _platform), do: {:error, :invalid_heart_rate_batch}

  defp cast_batch(batch) when is_map(batch) do
    sequence = get(batch, :sequence)
    offset = get(batch, :started_offset_ms)
    interval = get(batch, :interval_ms)
    bpm = get(batch, :bpm)

    if is_integer(sequence) and sequence >= 0 and is_integer(offset) and offset >= 0 and
         is_integer(interval) and interval in 1_000..60_000 and is_list(bpm) and bpm != [] and
         length(bpm) <= @max_samples and Enum.all?(bpm, &(is_integer(&1) and &1 in 0..400)) do
      {:ok, %{sequence: sequence, started_offset_ms: offset, interval_ms: interval, bpm: bpm}}
    else
      :error
    end
  end

  defp cast_batch(_batch), do: :error

  @doc """
  `{offset_ms, bpm}` samples of stored batches, in time order, noise dropped.
  """
  def samples(batches) do
    batches
    |> Enum.flat_map(fn batch ->
      batch.bpm
      |> Enum.with_index()
      |> Enum.map(fn {bpm, i} -> {batch.started_offset_ms + i * batch.interval_ms, bpm} end)
    end)
    |> Enum.filter(fn {_at, bpm} -> bpm >= @min_bpm and bpm <= @max_bpm end)
    |> Enum.sort()
    |> Enum.dedup_by(&elem(&1, 0))
  end

  @doc """
  The summary of `batches`. `sections` is `[{ordinal, from_ms, to_ms}]`;
  `max_hr` an integer or nil.
  """
  def summary(batches, sections, max_hr) do
    samples = samples(batches)
    interval = batches |> Enum.map(& &1.interval_ms) |> Enum.min(fn -> 5_000 end)

    %{
      samples: length(samples),
      average_bpm: average(samples),
      max_bpm: samples |> Enum.map(&elem(&1, 1)) |> Enum.max(fn -> nil end),
      min_bpm: samples |> Enum.map(&elem(&1, 1)) |> Enum.min(fn -> nil end),
      sections:
        Enum.map(sections, fn {ordinal, from, to} ->
          inside = Enum.filter(samples, fn {at, _bpm} -> at >= from and at < to end)

          %{
            section_ordinal: ordinal,
            average_bpm: average(inside),
            max_bpm: inside |> Enum.map(&elem(&1, 1)) |> Enum.max(fn -> nil end)
          }
        end),
      zones: zones(samples, max_hr, interval)
    }
  end

  @doc "`[{ordinal, from_ms, to_ms}]` from section times, back to back in ordinal order."
  def section_windows(section_times) do
    section_times
    |> Enum.sort()
    |> Enum.map_reduce(0, fn {ordinal, ms}, from -> {{ordinal, from, from + ms}, from + ms} end)
    |> elem(0)
  end

  defp zones(_samples, nil, _interval), do: []

  defp zones(samples, max_hr, interval) do
    Enum.map(@zones, fn {zone, low, high} ->
      count =
        Enum.count(samples, fn {_at, bpm} -> bpm >= low * max_hr and bpm < high * max_hr end)

      %{zone: zone, ms: count * interval}
    end)
  end

  defp average([]), do: nil

  defp average(samples),
    do: round(Enum.sum(Enum.map(samples, &elem(&1, 1))) / length(samples))

  defp get(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
end

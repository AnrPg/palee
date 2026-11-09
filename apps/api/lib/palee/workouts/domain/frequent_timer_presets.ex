defmodule Palee.Workouts.Domain.FrequentTimerPresets do
  @moduledoc """
  ADR-571: the timer chips a coach sees in the text-section editor, pure.

  The editor offers «Χωρίς χρόνο» (the `untimed` preset, the default of
  every section) plus three chips: the timers this coach uses most. Their
  history comes first; a coach with fewer than three of their own is
  topped up with the gym's most used timers, then with the stock ones, so
  the row is always three chips long and never repeats a timer.

  * Presets are compared by their canonical form (`canonical/1`): only the
    fields that format runs on, with the values the timer engine would use
    for the missing ones, so `%{"format" => "emom", "rounds" => nil}` and
    `%{"format" => "emom", "rounds" => 10, "interval_seconds" => 60}` are
    the same chip.
  * `untimed` never counts: it is always on the row as its own chip.
  * Ties go to the timer used most recently, then to the canonical order
    of the preset, so the row is stable between visits.
  """

  alias Palee.Execution.Domain.TimerPresets

  @size 3
  @untimed "untimed"

  # Stock chips for a coach and gym with no history yet: the three most
  # common CrossFit formats, at the lengths the timer engine already uses
  # when none is given.
  @stock [
    %{"format" => "amrap", "duration_seconds" => 720},
    %{"format" => "emom", "interval_seconds" => 60, "rounds" => 10},
    %{"format" => "for_time", "duration_seconds" => 720}
  ]

  @type usage :: %{preset: map(), uses: non_neg_integer(), last_used_at: term()}
  @type chip :: %{preset: map(), source: :author | :gym | :stock, uses: non_neg_integer()}

  def size, do: @size
  def untimed, do: %{"format" => @untimed}

  @doc """
  The chips: the author's most used timers, then the gym's, then stock.
  Each usage list holds raw presets (as stored) with their use counts.
  """
  @spec choose([usage()], [usage()]) :: [chip()]
  def choose(author_usage, gym_usage) do
    stock = Enum.map(@stock, &%{preset: canonical(&1), uses: 0, source: :stock})

    [{:author, author_usage}, {:gym, gym_usage}]
    |> Enum.flat_map(fn {source, usage} ->
      usage |> ranked() |> Enum.map(&Map.put(&1, :source, source))
    end)
    |> Enum.concat(stock)
    |> Enum.uniq_by(& &1.preset)
    |> Enum.take(@size)
    |> Enum.map(&Map.take(&1, [:preset, :source, :uses]))
  end

  @doc "Merges usage rows by canonical preset and orders them, most used first."
  def ranked(usage) do
    usage
    |> Enum.flat_map(fn row ->
      case canonical(row.preset) do
        nil -> []
        %{"format" => @untimed} -> []
        preset -> [%{row | preset: preset}]
      end
    end)
    |> Enum.group_by(& &1.preset)
    |> Enum.map(fn {preset, rows} ->
      %{
        preset: preset,
        uses: rows |> Enum.map(& &1.uses) |> Enum.sum(),
        last_used_at: rows |> Enum.map(& &1.last_used_at) |> Enum.reject(&is_nil/1) |> latest()
      }
    end)
    |> Enum.sort_by(&{-&1.uses, sort_time(&1.last_used_at), sort_key(&1.preset)})
  end

  @doc """
  A preset reduced to what its format runs on, with the timer engine's own
  values for the missing ones; nil when it is not a preset.
  """
  def canonical(raw) do
    case TimerPresets.parse(raw) do
      nil -> nil
      preset -> reduce(preset)
    end
  end

  defp reduce(%{"format" => "untimed"}), do: untimed()

  defp reduce(%{"format" => "amrap"} = preset),
    do: %{"format" => "amrap", "duration_seconds" => preset["duration_seconds"] || 720}

  defp reduce(%{"format" => "for_time"} = preset),
    do: compact(%{"format" => "for_time", "duration_seconds" => preset["duration_seconds"]})

  defp reduce(%{"format" => "emom"} = preset),
    do: %{
      "format" => "emom",
      "interval_seconds" => preset["interval_seconds"] || 60,
      "rounds" => preset["rounds"] || 10
    }

  defp reduce(%{"format" => "death_by"} = preset),
    do:
      compact(%{
        "format" => "death_by",
        "interval_seconds" => preset["interval_seconds"] || 60,
        "rounds" => preset["rounds"]
      })

  defp reduce(%{"format" => format} = preset) when format in ["tabata", "custom_hiit"],
    do:
      compact(%{
        "format" => format,
        "work_seconds" => preset["work_seconds"] || 20,
        "rest_seconds" => preset["rest_seconds"] || if(format == "tabata", do: 10),
        "rounds" => preset["rounds"] || 8
      })

  defp compact(preset),
    do: preset |> Enum.reject(fn {_key, item} -> is_nil(item) end) |> Map.new()

  defp latest([]), do: nil
  defp latest(times), do: Enum.max(times, &later_or_equal?/2)

  defp later_or_equal?(%DateTime{} = a, %DateTime{} = b), do: DateTime.compare(a, b) != :lt

  defp later_or_equal?(%NaiveDateTime{} = a, %NaiveDateTime{} = b),
    do: NaiveDateTime.compare(a, b) != :lt

  defp later_or_equal?(a, b), do: a >= b

  # Most recent first; no known time last.
  defp sort_time(nil), do: {1, 0}
  defp sort_time(%DateTime{} = time), do: {0, -DateTime.to_unix(time, :microsecond)}

  defp sort_time(%NaiveDateTime{} = time),
    do: sort_time(DateTime.from_naive!(time, "Etc/UTC"))

  defp sort_time(_other), do: {1, 0}

  defp sort_key(preset), do: preset |> Enum.sort() |> inspect()
end

defmodule Palee.Devices.Domain.WatchContract do
  @moduledoc """
  The shared contract between the server, the phone app and the watch app
  (ADR-375, CP-D8). The watch never talks to the server: the phone app
  relays (WatchConnectivity on iOS, the Wearable Data Layer on Android).

  * **What the watch shows**: the running segment's timer, its label, the
    round, up to three movements of the segment, the heart rate, and the
    pace against the previous attempt (ADR-374) when there is one.
  * **What the watch can do**: `next` (end the segment), `round` (finish a
    round), `pause`, `resume`, `finish`. Each is a command with a client id
    the phone turns into the existing idempotent calls (progress with an
    `operation_id`, split marks, completion), so a command sent twice after
    being offline acts once.
  * **Offline**: the watch keeps running from the plan it was given; it
    queues commands, split marks and heart-rate batches in order and the
    phone sends them when it can. Heart-rate batches are numbered per
    execution (`sequence`) and stored once.

  `version/0` changes only when a field changes meaning or is removed; a
  watch app with an older `contract_version` gets `upgrade_required` from
  the pairing call.
  """

  @version 1
  @min_supported 1
  @platforms ~w(apple_watch wear_os)
  @commands ~w(next round pause resume finish)
  @max_movements 3
  @max_pace_points 300
  @heart_rate_interval_ms 5_000

  @settings_defaults %{
    "show_heart_rate" => true,
    "show_pace" => true,
    "haptics" => true,
    "max_hr" => nil
  }

  def version, do: @version
  def min_supported, do: @min_supported
  def platforms, do: @platforms
  def commands, do: @commands
  def settings_defaults, do: @settings_defaults
  def heart_rate_interval_ms, do: @heart_rate_interval_ms

  @doc "Whether a watch app speaking `version` is still served."
  def supported?(version) when is_integer(version),
    do: version >= @min_supported and version <= @version

  def supported?(_version), do: false

  @doc """
  The watch settings after `changes` (string or atom keys): booleans, and
  `max_hr` 120–230 or nil (heart-rate zones only appear with it).
  """
  def merge_settings(current, changes) when is_map(changes) do
    current = Map.merge(@settings_defaults, current || %{})

    Enum.reduce_while(changes, {:ok, current}, fn {key, value}, {:ok, acc} ->
      key = to_string(key)

      cond do
        key in ~w(show_heart_rate show_pace haptics) and is_boolean(value) ->
          {:cont, {:ok, Map.put(acc, key, value)}}

        key == "max_hr" and (is_nil(value) or (is_integer(value) and value in 120..230)) ->
          {:cont, {:ok, Map.put(acc, key, value)}}

        true ->
          {:halt, {:error, :invalid_watch_settings}}
      end
    end)
  end

  def merge_settings(_current, _changes), do: {:error, :invalid_watch_settings}

  @doc """
  The plan the phone hands the watch for one execution: its segments in
  compact form, where it is now, and the pace line to race.
  """
  def plan(execution, segments, pace_checkpoints, settings) do
    settings = Map.merge(@settings_defaults, settings || %{})

    %{
      contract_version: @version,
      execution_id: execution.id,
      title: Map.get(execution, :workout_title),
      status: to_string(execution.status),
      progress: %{
        current_segment_index: execution.current_segment_index || 0,
        lock_version: execution.lock_version || 1,
        total_elapsed_ms: execution.total_elapsed_ms || 0,
        paused_elapsed_ms: execution.paused_elapsed_ms || 0,
        segment_started_at_utc: execution.segment_started_at_utc
      },
      segments: segments |> Enum.with_index() |> Enum.map(&segment/1),
      pace:
        if(settings["show_pace"],
          do: pace_checkpoints |> Enum.take(@max_pace_points) |> Enum.map(&pace_point/1),
          else: []
        ),
      commands: @commands,
      heart_rate: %{
        enabled: settings["show_heart_rate"] == true,
        interval_ms: @heart_rate_interval_ms,
        max_hr: settings["max_hr"]
      },
      haptics: settings["haptics"] == true
    }
  end

  defp segment({segment, index}) do
    %{
      index: index,
      kind: to_string(get(segment, :kind)),
      phase: to_string(get(segment, :phase) || "work"),
      duration_seconds: get(segment, :duration_seconds),
      round: get(segment, :round),
      total_rounds: get(segment, :total_rounds),
      section_name: get(segment, :section_name),
      label: get(segment, :label),
      label_key: get(segment, :label_key),
      label_params: get(segment, :label_params) || %{},
      movements:
        segment
        |> get(:exercises)
        |> List.wrap()
        |> Enum.take(@max_movements)
        |> Enum.map(&movement/1)
        |> Enum.reject(&is_nil/1),
      scoreable: get(segment, :scoreable) == true
    }
  end

  defp movement(exercise) when is_map(exercise) do
    case get(exercise, :name) do
      name when is_binary(name) and name != "" ->
        %{
          name: String.slice(name, 0, 40),
          amount: get(exercise, :prescription_value),
          unit: get(exercise, :prescription_unit)
        }

      _no_name ->
        nil
    end
  end

  defp movement(_exercise), do: nil

  defp pace_point(checkpoint),
    do: Map.take(checkpoint, [:key, :section_ordinal, :phase, :round, :at_ms])

  defp get(map, key) when is_map(map), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
end

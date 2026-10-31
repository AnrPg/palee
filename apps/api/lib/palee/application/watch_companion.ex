defmodule Palee.Application.WatchCompanion do
  @moduledoc """
  The watch companion (ADR-375, CP-D8), server side. The watch app talks
  only to the phone app; the phone calls these on the person's behalf:

    * `list/1`, `pair/3`, `unpair/2` – Εγώ › Συνδεδεμένες συσκευές › «Ρολόι»;
    * `plan/3` – what the watch runs for one execution (segments, where it
      is, the pace line of ADR-374, the watch's settings);
    * `record_heart_rate/3` – numbered batches of heart rate, once each,
      only with the `health_data` consent;
    * `heart_rate_summary/2` – average, highest, per section and zones.

  Commands from the watch (next, round, pause, resume, finish) reuse the
  execution's idempotent progress, split and completion calls.
  """

  alias Palee.Application.{Clock, ExecutionPacer, ExecutionTimerSequence, WellnessConsent}
  alias Palee.{Devices, Execution}
  alias Palee.Devices.WatchStore
  alias Palee.Execution.ExecutionStore

  def list(%{user_id: user_id} = context) do
    links = WatchStore.with_context(context, fn -> WatchStore.list_links(user_id) end)
    {:ok, %{contract: contract(), watches: Enum.map(links, &present/1)}}
  end

  def pair(%{user_id: user_id} = context, platform, params) do
    version = param(params, "contract_version")

    cond do
      platform not in Devices.watch_platforms() ->
        {:error, :unknown_watch_platform}

      not Devices.watch_supported?(version) ->
        {:error, :watch_upgrade_required}

      true ->
        now = Clock.now()

        WatchStore.with_context(context, fn ->
          link = WatchStore.get_link(user_id, platform)

          with {:ok, settings} <-
                 Devices.merge_watch_settings(link && link.settings, param(params, "settings") || %{}),
               {:ok, saved} <-
                 WatchStore.save_link(link, %{
                   user_id: user_id,
                   platform: platform,
                   device_name: param(params, "device_name"),
                   app_version: param(params, "app_version"),
                   contract_version: version,
                   settings: settings,
                   paired_at: (link && link.paired_at) || now,
                   last_seen_at: now
                 }) do
            {:ok, present(saved)}
          end
        end)
    end
  end

  def unpair(%{user_id: user_id} = context, platform) do
    case WatchStore.with_context(context, fn -> WatchStore.delete_link(user_id, platform) end) do
      0 -> {:error, :watch_not_paired}
      _deleted -> :ok
    end
  end

  def plan(%{user_id: user_id} = context, execution_id, platform) do
    with {:ok, execution} <- own_execution(context, execution_id),
         {:ok, pacer} <- ExecutionPacer.show(context, execution_id) do
      {workout, segments} = ExecutionTimerSequence.with_workout(execution)

      settings =
        case platform && WatchStore.with_context(context, fn -> WatchStore.get_link(user_id, platform) end) do
          %{settings: settings} -> settings
          _none -> %{}
        end

      pace =
        Enum.map(pacer.checkpoints, &Map.put(&1, :at_ms, &1.ghost_at_ms))

      execution = Map.put(execution, :workout_title, workout && workout.title)
      {:ok, Devices.watch_plan(execution, segments, pace, settings)}
    end
  end

  def record_heart_rate(%{user_id: user_id} = context, execution_id, params) do
    with :ok <- WellnessConsent.require(context),
         {:ok, execution} <- own_execution(context, execution_id),
         {:ok, rows} <-
           Devices.cast_heart_rate(param(params, "batches"), param(params, "platform")) do
      WatchStore.with_context(context, fn ->
        {:ok, stored} = WatchStore.insert_heart_rate(execution.id, user_id, rows, Clock.now())
        {:ok, %{stored: stored, total: length(WatchStore.list_heart_rate(execution.id))}}
      end)
    end
  end

  def heart_rate_summary(%{user_id: user_id} = context, execution_id) do
    with {:ok, execution} <- own_execution(context, execution_id) do
      {batches, links} =
        WatchStore.with_context(context, fn ->
          {WatchStore.list_heart_rate(execution.id), WatchStore.list_links(user_id)}
        end)

      segments = ExecutionTimerSequence.for_execution(execution)

      windows =
        execution.section_elapsed_ms
        |> Execution.pace_section_times(Execution.split_section_ordinals(segments))
        |> Devices.heart_rate_windows()

      max_hr = Enum.find_value(links, &Map.get(&1.settings || %{}, "max_hr"))

      {:ok, Map.put(Devices.heart_rate_summary(batches, windows, max_hr), :execution_id, execution.id)}
    end
  end

  defp own_execution(%{user_id: user_id} = context, execution_id) do
    ExecutionStore.with_user_context(context, fn ->
      case Execution.get_execution(execution_id) do
        %{user_id: ^user_id} = execution -> {:ok, execution}
        _other -> {:error, :not_found}
      end
    end)
  end

  defp contract do
    %{
      version: Devices.watch_contract_version(),
      platforms: Devices.watch_platforms()
    }
  end

  defp present(link) do
    %{
      platform: link.platform,
      device_name: link.device_name,
      app_version: link.app_version,
      contract_version: link.contract_version,
      settings: Map.merge(Devices.watch_settings_defaults(), link.settings || %{}),
      paired_at: link.paired_at,
      last_seen_at: link.last_seen_at,
      needs_upgrade: link.contract_version < Devices.watch_contract_version()
    }
  end

  defp param(params, key) when is_map(params),
    do: Map.get(params, key, Map.get(params, String.to_existing_atom(key)))

  defp param(_params, _key), do: nil
end

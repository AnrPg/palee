defmodule Palee.Application.WatchCompanion do
  @moduledoc """
  The watch companion (ADR-375, CP-D8), server side. The watch app talks
  only to the phone app; the phone calls these on the person's behalf:

    * `list/1`, `pair/3`, `unpair/2` – Εγώ › Συνδεδεμένες συσκευές › «Ρολόι»;
    * `plan/3` – what the watch runs for one execution (segments, where it
      is, the pace line of ADR-374, the watch's settings);
    * `record_heart_rate/3` – numbered batches of heart rate, once each,
      only with the `health_data` consent;
    * `heart_rate_summary/2` – average, highest, per section and zones;
    * `offer/3`, `answer_offer/3` – ANR's D8 rules: whether the phone asks
      «Το χρονόμετρο και στο ρολόι;», starts the watch on its own or leaves
      it, when a WOD is opened for execution (never a notification).

  Commands from the watch (next, round, pause, resume, finish) reuse the
  execution's idempotent progress, split and completion calls.
  """

  alias Palee.Application.{Clock, ExecutionPacer, ExecutionTimerSequence, WellnessConsent}
  alias Palee.{Devices, Execution, Organizations, Scheduling}
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
                 Devices.merge_watch_settings(
                   link && link.settings,
                   param(params, "settings") || %{}
                 ),
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
        case platform &&
               WatchStore.with_context(context, fn -> WatchStore.get_link(user_id, platform) end) do
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

      {:ok,
       Map.put(Devices.heart_rate_summary(batches, windows, max_hr), :execution_id, execution.id)}
    end
  end

  @doc """
  Called by the phone when a WOD is opened for execution and it sees a
  watch: `%{"platform", "watch_connected"}`. Returns `%{mode: "ask" |
  "start" | "none", reason, asked_count, ask_limit}`; an `ask` or `start`
  is remembered for this execution (asked once, counted once).
  """
  def offer(%{user_id: user_id} = context, execution_id, params) do
    platform = param(params, "platform")

    with :ok <- known_platform(platform),
         {:ok, execution} <- own_execution(context, execution_id) do
      facts = offer_facts(context, execution, param(params, "watch_connected") == true)
      outcome = Devices.decide_watch_offer(facts)

      offer =
        case {facts.existing, Devices.watch_offer_mode(outcome)} do
          {nil, mode} when is_binary(mode) ->
            {:ok, saved} =
              WatchStore.with_context(context, fn ->
                WatchStore.save_offer(nil, %{
                  execution_id: execution.id,
                  user_id: user_id,
                  platform: platform,
                  mode: mode
                })
              end)

            saved

          {existing, _mode} ->
            existing
        end

      newly_asked = if (is_nil(facts.existing) and offer) && offer.mode == "asked", do: 1, else: 0

      {:ok,
       present_offer(outcome, offer, %{facts | asked_before: facts.asked_before + newly_asked})}
    end
  end

  @doc "The person's answer to the question: `%{\"answer\" => \"yes\" | \"no\"}`."
  def answer_offer(%{user_id: _user_id} = context, execution_id, params) do
    answer = param(params, "answer")

    with :ok <- known_answer(answer),
         {:ok, execution} <- own_execution(context, execution_id) do
      WatchStore.with_context(context, fn ->
        offer = WatchStore.get_offer(execution.id)

        if Devices.watch_offer_answerable?(offer) do
          {:ok, saved} = WatchStore.save_offer(offer, %{answer: answer})
          {:ok, %{mode: if(answer == "yes", do: "start", else: "none"), answer: saved.answer}}
        else
          {:error, :watch_offer_not_asked}
        end
      end)
    end
  end

  defp offer_facts(%{user_id: user_id} = context, execution, connected?) do
    {existing, asked_before} =
      WatchStore.with_context(context, fn ->
        {WatchStore.get_offer(execution.id), WatchStore.count_asked_offers(user_id)}
      end)

    class_wod? = to_string(execution.source) == "class_booking"

    %{
      execution_open?: to_string(execution.status) in ~w(active paused),
      watch_connected?: connected?,
      class_wod?: class_wod?,
      checked_in?: class_wod? and checked_in?(execution),
      box_member?: Organizations.list_memberships(user_id) != [],
      asked_before: asked_before,
      existing: existing
    }
  end

  defp checked_in?(%{organization_id: organization_id, user_id: user_id} = execution)
       when is_binary(organization_id) and is_binary(execution.source_reference_id) do
    context = %{organization_id: organization_id, user_id: user_id}

    with %{scheduled_class_id: slot_id} when is_binary(slot_id) <-
           Scheduling.get_booking_execution_access(
             context,
             execution.source_reference_id,
             user_id
           ),
         %{status: "attended"} <-
           Scheduling.get_attendance_for_user_class(context, user_id, slot_id) do
      true
    else
      _not_checked_in -> false
    end
  end

  defp checked_in?(_execution), do: false

  defp present_offer({mode, reason}, offer, facts) do
    %{
      mode: to_string(mode),
      reason: to_string(reason),
      answer: offer && offer.answer,
      asked_count: facts.asked_before,
      ask_limit: if(facts.box_member?, do: Devices.watch_offer_ask_limit())
    }
  end

  defp known_platform(platform) do
    if platform in Devices.watch_platforms(), do: :ok, else: {:error, :unknown_watch_platform}
  end

  defp known_answer(answer) when answer in ~w(yes no), do: :ok
  defp known_answer(_answer), do: {:error, :invalid_watch_offer_answer}

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

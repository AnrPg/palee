defmodule Palee.Application.Channels.ClassNotices do
  @moduledoc """
  «Ενημέρωση συμμετεχόντων» from a class (ADR-385, screen 4 option Γ): the
  app first, SMS only for the participants the app cannot reach.

  A participant (an approved or pending booking of a member) with a push
  device gets the notice in the app (`box_message`, free). The rest get it
  by SMS through `SendThroughChannel` (consent, quiet hours, budget and
  demo mode all apply); whoever has neither has no way. `preview/3` counts
  the three groups and prices the SMS before anything is sent; `deliver/3`
  sends with one idempotency key per person, so a second press sends
  nothing twice.

  Kinds: `cancelled` and `changed` use Palee's wording (`class_cancelled`,
  `class_changed`) and go at once (urgent); `free` sends the staff's own
  `text` (`box_message`) and waits for quiet hours unless `urgent`.
  """

  alias Palee.Application.ClassLocation
  alias Palee.Application.Channels.SendThroughChannel
  alias Palee.Channels.Domain.Templates
  alias Palee.{Notifications, Scheduling}
  alias Palee.TimeZones.ZonedTime

  @kinds ~w(cancelled changed free)
  @participants [:approved, :pending]
  @max_text 300

  @doc "Counts and cost of a notice, nothing sent."
  def preview(context, params, now \\ DateTime.utc_now()) do
    with {:ok, notice} <- notice(context, params, now) do
      plans = Enum.map(notice.people, &plan(context, notice, &1, now))
      {:ok, summary(notice, plans)}
    end
  end

  @doc "Sends the notice: in the app to those with a device, by SMS to the rest."
  def deliver(context, params, now \\ DateTime.utc_now()) do
    with {:ok, notice} <- notice(context, params, now),
         {:ok, key} <- client_key(params) do
      plans =
        Enum.map(notice.people, fn person ->
          plan = plan(context, notice, person, now)
          send_planned(context, notice, plan, key, now)
        end)

      {:ok, summary(notice, plans)}
    end
  end

  defp notice(context, params, now) do
    kind = param(params, :kind)
    text = params |> param(:text) |> clean()

    errors =
      %{}
      |> add(kind not in @kinds, :kind, "invalid")
      |> add(kind == "free" and is_nil(text), :text, "required")
      |> add(is_binary(text) and String.length(text) > @max_text, :text, "too_long")

    with :ok <- no_errors(errors),
         {:ok, slot_id} <- slot_id(params),
         :ok <- ClassLocation.authorize_class(context, slot_id),
         [slot] <- Scheduling.list_slots_by_ids(context, [slot_id]) do
      env = SendThroughChannel.env(context, now)

      {:ok,
       %{
         slot: slot,
         kind: kind,
         text: text,
         urgent: kind in ~w(cancelled changed) or param(params, :urgent) == true,
         class: slot.name || class_type_name(slot),
         when: ZonedTime.format(slot.scheduled_at, env.time_zone),
         box: env.box_name,
         locale: locale(param(params, :locale)),
         people: participants(slot)
       }}
    else
      [] -> {:error, :not_found}
      error -> error
    end
  end

  defp participants(slot) do
    (slot.bookings || [])
    |> Enum.filter(&(&1.status in @participants and is_binary(&1.user_id)))
    |> Enum.map(& &1.user_id)
    |> Enum.uniq()
  end

  # One person: the app when they have a device, else an SMS preview.
  defp plan(context, notice, user_id, now) do
    if Notifications.reachable_in_app?(user_id) do
      %{user_id: user_id, route: :app}
    else
      case SendThroughChannel.preview(context, sms_params(notice, user_id, "preview"), now) do
        {:ok, preview} -> %{user_id: user_id, route: :sms, preview: preview}
        {:error, reason} -> %{user_id: user_id, route: :none, reason: reason}
      end
    end
  end

  defp send_planned(context, notice, %{route: :app} = plan, key, _now) do
    _result =
      Notifications.enqueue_message_to_member(:box_message, %{
        user_id: plan.user_id,
        organization_id: context.organization_id,
        body: app_text(notice),
        url: "/box/schedule",
        dedupe_key: "class_notice:#{notice.slot.id}:#{key}:#{plan.user_id}"
      })

    plan
  end

  defp send_planned(context, notice, %{route: :sms} = plan, key, now) do
    params = sms_params(notice, plan.user_id, "class_notice:#{notice.slot.id}:#{key}")

    case SendThroughChannel.call(context, params, now) do
      {:ok, _message} -> plan
      {:error, reason} -> %{user_id: plan.user_id, route: :none, reason: reason}
    end
  end

  defp send_planned(_context, _notice, plan, _key, _now), do: plan

  defp sms_params(notice, user_id, key) do
    {template, variables} = template(notice)

    %{
      user_id: user_id,
      template_key: template,
      variables: variables,
      purpose: "service",
      channels: ["sms"],
      urgent: notice.urgent,
      idempotency_key: "#{key}:#{user_id}",
      source: "staff",
      source_ref: "class:#{notice.slot.id}"
    }
  end

  defp template(%{kind: "cancelled"} = notice),
    do: {"class_cancelled", %{"class" => notice.class, "when" => notice.when}}

  defp template(%{kind: "changed"} = notice),
    do: {"class_changed", %{"class" => notice.class, "when" => notice.when}}

  defp template(notice), do: {"box_message", %{"text" => notice.text}}

  # The app notice: the staff's words, else Palee's SMS wording in the
  # language of the staff member who sends it.
  defp app_text(%{text: text}) when is_binary(text), do: text

  defp app_text(notice) do
    {key, variables} = template(notice)

    with {:ok, {body, _locale}} <- Templates.body(key, notice.locale, %{}),
         {:ok, text} <- Templates.render(body, Map.put(variables, "box", notice.box)) do
      text
    else
      _error -> "#{notice.class} · #{notice.when}"
    end
  end

  defp locale(locale) when is_binary(locale) do
    if locale in Templates.locales(), do: locale, else: "el"
  end

  defp locale(_locale), do: "el"

  defp summary(notice, plans) do
    sms = Enum.filter(plans, &(&1.route == :sms))
    none = Enum.filter(plans, &(&1.route == :none))
    first = List.first(sms)

    %{
      slot_id: notice.slot.id,
      kind: notice.kind,
      urgent: notice.urgent,
      participants: length(plans),
      in_app: Enum.count(plans, &(&1.route == :app)),
      sms: length(sms),
      unreachable: length(none),
      unreachable_reasons: none |> Enum.frequencies_by(&reason_code(&1.reason)),
      estimated_cost_cents: sms |> Enum.map(& &1.preview.estimated_cost_cents) |> Enum.sum(),
      currency: (first && first.preview.currency) || "EUR",
      budget: first && first.preview.budget,
      sample:
        first &&
          Map.take(first.preview, [:body, :segments, :release_at, :held_for_quiet_hours]),
      sms_blocked: blocked(none)
    }
  end

  # When every SMS failed for the box's own reason (no connection, demo
  # mode, no cap typed, over budget), the screen says it once instead of per person.
  @box_reasons ~w(channels_not_connected channels_demo_mode channels_connection_invalid
                  channel_not_enabled channel_budget_missing channel_budget_exceeded)
  defp blocked(none) do
    none
    |> Enum.map(&reason_code(&1.reason))
    |> Enum.find(&(&1 in @box_reasons))
  end

  defp reason_code(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp reason_code({:invalid_fields, _errors}), do: "invalid_fields"
  defp reason_code(_reason), do: "error"

  defp class_type_name(%{class_type: %{name: name}}), do: name
  defp class_type_name(_slot), do: nil

  defp slot_id(params) do
    case Ecto.UUID.cast(param(params, :slot_id)) do
      {:ok, id} -> {:ok, id}
      :error -> {:error, {:invalid_fields, %{slot_id: "invalid"}}}
    end
  end

  defp client_key(params) do
    case param(params, :idempotency_key) do
      key when is_binary(key) and byte_size(key) in 1..80 -> {:ok, key}
      _missing -> {:error, {:invalid_fields, %{idempotency_key: "required"}}}
    end
  end

  defp clean(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      text -> text
    end
  end

  defp clean(_value), do: nil

  defp add(errors, true, field, reason), do: Map.put(errors, field, reason)
  defp add(errors, false, _field, _reason), do: errors

  defp no_errors(errors) when errors == %{}, do: :ok
  defp no_errors(errors), do: {:error, {:invalid_fields, errors}}

  defp param(params, key) when is_map(params),
    do: Map.get(params, key, Map.get(params, Atom.to_string(key)))
end

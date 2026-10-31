defmodule Palee.Application.Automations.DispatchAutomations do
  @moduledoc """
  ADR-346: the outbox worker. Claims the box's due automatic messages
  (`FOR UPDATE SKIP LOCKED`), decides again whether each may go
  (`DeliveryPolicy`), writes its text in the person's language (or the
  box's own words) and hands it to the first of the recipe's channels that
  reaches the person. A channel that can never reach them passes to the
  next; a passing failure is tried again later with growing waits.

  A message sent to a lead leaves a line in the lead's history.
  """

  require Logger

  alias Palee.{Automations, Identity, Leads, Organizations}
  alias Palee.Automations.Delivery

  @batch 50

  @urls %{
    "renewal_reminder" => "/me/payments",
    "missed_classes" => "/schedule"
  }

  @doc "Sends the box's due messages. Answers `%{sent, skipped, retried, failed}`."
  def run(%{organization_id: organization_id} = context, now \\ Automations.now()) do
    deliveries = Automations.claim_due(context, now, @batch)

    box =
      if deliveries == [],
        do: nil,
        else: %{
          name: box_name(organization_id),
          time_zone: Organizations.organization_timezone(organization_id),
          automations: context |> Automations.list_automations() |> Map.new(&{&1.recipe, &1})
        }

    deliveries
    |> Enum.map(&process(context, box, &1, now))
    |> Enum.frequencies()
    |> then(&Map.merge(%{sent: 0, skipped: 0, retried: 0, failed: 0}, &1))
  end

  defp box_name(organization_id) do
    case Organizations.get_by_id(organization_id) do
      %{name: name} -> name
      _none -> ""
    end
  end

  defp process(context, box, %Delivery{} = delivery, now) do
    {:ok, recipe} = Automations.fetch_recipe(delivery.recipe)
    automation = Map.get(box.automations, delivery.recipe)
    recipient = recipient(context, delivery)

    facts = %{
      recipe: recipe,
      automation: automation,
      recipient: recipient,
      preferences: preferences(context, recipient),
      settings: Automations.settings(recipe, automation && automation.settings),
      channels: channels(recipe, automation),
      time_zone: box.time_zone,
      now: now
    }

    case Automations.decide(facts) do
      {:send, channels} ->
        message = message(context, box, delivery, recipe, automation, recipient)
        send_first(context, delivery, recipient, message, channels, now)

      {:defer, at} ->
        finish(context, delivery, %{status: "pending", due_at: at, claimed_at: nil})
        :retried

      {:skip, reason} ->
        finish(context, delivery, %{status: "skipped", skip_reason: reason})
        :skipped

      {:cancel, reason} ->
        finish(context, delivery, %{status: "cancelled", skip_reason: reason})
        :skipped
    end
  rescue
    error ->
      Logger.error(
        "automation_delivery_crashed id=#{delivery.id} " <>
          Exception.format(:error, error, __STACKTRACE__)
      )

      retry(context, delivery, "crashed", now)
  end

  # The box's order, limited to channels this deployment has.
  defp channels(recipe, automation) do
    chosen =
      case automation do
        %{channels: [_ | _] = channels} -> channels
        _default -> recipe.channels
      end

    Enum.filter(chosen, &Automations.channel/1)
  end

  defp send_first(context, delivery, _recipient, _message, [], _now) do
    finish(context, delivery, %{status: "skipped", skip_reason: "unreachable"})
    :skipped
  end

  defp send_first(context, delivery, recipient, message, [name | rest], now) do
    adapter = Automations.channel(name)

    if adapter.reachable?(recipient) do
      case adapter.deliver(message) do
        {:ok, ref} ->
          finish(context, delivery, %{
            status: "sent",
            channel: name,
            sent_at: now,
            external_ref: ref && to_string(ref),
            last_error: nil
          })

          note_lead(context, recipient, delivery, name, now)
          :sent

        {:error, {:permanent, _reason}} ->
          send_first(context, delivery, recipient, message, rest, now)

        {:error, {:transient, reason}} ->
          retry(context, delivery, inspect(reason), now)
      end
    else
      send_first(context, delivery, recipient, message, rest, now)
    end
  end

  defp retry(context, delivery, error, now) do
    case Automations.after_failure(delivery.attempts, now) do
      {:retry, at} ->
        finish(context, delivery, %{
          status: "pending",
          due_at: at,
          claimed_at: nil,
          last_error: String.slice(error, 0, 255)
        })

        :retried

      :give_up ->
        finish(context, delivery, %{status: "failed", last_error: String.slice(error, 0, 255)})
        :failed
    end
  end

  defp finish(context, delivery, changes) do
    case Automations.finish(context, delivery.id, changes) do
      {:ok, _delivery} ->
        :ok

      {:error, reason} ->
        Logger.error("automation_delivery_finish_failed id=#{delivery.id} #{inspect(reason)}")
    end
  end

  # ── The person ──────────────────────────────────────────────────────────

  defp recipient(context, %Delivery{user_id: user_id}) when is_binary(user_id) do
    case Identity.find_by_id(user_id) do
      nil ->
        nil

      account ->
        %{
          kind: :member,
          organization_id: context.organization_id,
          user_id: account.id,
          name: account.nickname,
          email: account.email,
          locale: account.preferred_locale,
          in_box: Organizations.member_roles(context.organization_id, user_id) != []
        }
    end
  end

  defp recipient(context, %Delivery{lead_id: lead_id}) when is_binary(lead_id) do
    case Leads.get(context, lead_id) do
      nil ->
        nil

      lead ->
        %{
          kind: :lead,
          organization_id: context.organization_id,
          lead_id: lead.id,
          user_id: nil,
          name: lead.name,
          email: lead.email,
          phone: lead.phone,
          locale: lead.locale,
          consent_contact_at: lead.consent_contact_at,
          consent_marketing_at: lead.consent_marketing_at,
          marketing_opted_out_at: lead.marketing_opted_out_at
        }
    end
  end

  defp recipient(_context, _delivery), do: nil

  defp preferences(context, %{kind: :member, user_id: user_id}),
    do: Automations.get_preference(context, user_id)

  defp preferences(_context, _recipient), do: nil

  # ── The words ───────────────────────────────────────────────────────────

  defp message(context, box, delivery, recipe, automation, recipient) do
    {default_subject, default_body} = Automations.default_text(recipe.key, recipient.locale)

    vars =
      (delivery.data || %{})
      |> Map.merge(%{
        "first_name" => first_name(recipient.name),
        "box" => box.name,
        "ends_on" => ends_on(delivery.data, recipient.locale)
      })

    %{
      organization_id: context.organization_id,
      delivery_id: delivery.id,
      recipe: recipe.key,
      purpose: recipe.purpose,
      recipient: recipient,
      subject: Automations.render((automation && automation.subject) || default_subject, vars),
      body: Automations.render((automation && automation.body) || default_body, vars),
      url: Map.get(@urls, recipe.key, "/"),
      box_name: box.name
    }
  end

  defp first_name(name) when is_binary(name), do: name |> String.split() |> List.first() || ""
  defp first_name(_name), do: ""

  # Dates read the European way the app uses (day/month/year).
  defp ends_on(%{"ends_on" => iso}, _locale) when is_binary(iso) do
    case Date.from_iso8601(iso) do
      {:ok, date} -> Calendar.strftime(date, "%d/%m/%Y")
      _error -> iso
    end
  end

  defp ends_on(_data, _locale), do: nil

  defp note_lead(context, %{kind: :lead, lead_id: lead_id}, delivery, channel, now) do
    Leads.add_event(context, %{
      lead_id: lead_id,
      kind: "message_sent",
      at: now,
      data: %{"recipe" => delivery.recipe, "channel" => channel}
    })
  end

  defp note_lead(_context, _recipient, _delivery, _channel, _now), do: :ok
end

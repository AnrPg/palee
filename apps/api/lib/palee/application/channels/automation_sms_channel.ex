defmodule Palee.Application.Channels.AutomationSmsChannel do
  @moduledoc """
  The `sms` channel of W2's automations (CP-C2, ADR-351): a thin wrapper
  that fits `Palee.Automations.Ports.Channel` (`channel/0`, `reachable?/1`,
  `deliver/1`) over `SendThroughChannel`. The integrator registers it as
  `config :palee, :automation_channels, %{"sms" => #{inspect(__MODULE__)}}`.

  Consent, STOP, quiet hours and the box's budget are checked here, on
  the Channels side. Anything that means «SMS cannot reach this person
  for this message» answers `{:error, {:permanent, reason}}`, so the
  automation falls through to its next channel; an outage of the
  provider is retried by the Channels outbox itself, so the automation
  sees the message accepted (`{:ok, message_id}`).
  """

  alias Palee.Application.Channels.SendThroughChannel
  alias Palee.Channels

  def channel, do: "sms"

  @doc """
  Whether the recipient has an SMS number and consent in the box. Needs
  the box: `recipient.organization_id` (else it answers true and
  `deliver/1` decides). The purpose is unknown here, so either consent
  counts.
  """
  def reachable?(%{organization_id: organization_id} = recipient)
      when is_binary(organization_id) do
    context = %{organization_id: organization_id}
    person = person(recipient)

    Enum.any?(~w(service marketing), &Channels.consented?(context, person, "sms", &1))
  end

  def reachable?(_recipient), do: true

  @doc "Queues the SMS of one automation delivery (idempotent per `delivery_id`)."
  def deliver(%{organization_id: organization_id, delivery_id: delivery_id} = message) do
    text =
      [message[:body], message[:url]]
      |> Enum.filter(&(is_binary(&1) and &1 != ""))
      |> Enum.join(" ")

    params =
      message.recipient
      |> person()
      |> Map.merge(%{
        template_key: "box_message",
        variables: %{"text" => text, "box" => message[:box_name]},
        purpose: purpose(message[:purpose]),
        channels: ["sms"],
        idempotency_key: "automation:#{delivery_id}",
        source: "automation",
        source_ref: message[:recipe] && "automation:#{message[:recipe]}"
      })
      |> Map.reject(fn {_key, value} -> is_nil(value) end)

    case SendThroughChannel.call(%{organization_id: organization_id}, params) do
      {:ok, queued} -> {:ok, queued.id}
      {:error, reason} -> {:error, {:permanent, reason}}
    end
  end

  defp person(%{kind: :lead, lead_id: id}) when is_binary(id), do: %{lead_id: id}
  defp person(%{user_id: id}) when is_binary(id), do: %{user_id: id}
  defp person(%{lead_id: id}) when is_binary(id), do: %{lead_id: id}
  defp person(_recipient), do: %{}

  defp purpose(:marketing), do: "marketing"
  defp purpose("marketing"), do: "marketing"
  defp purpose(_purpose), do: "service"
end

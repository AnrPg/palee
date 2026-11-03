defmodule Palee.Infrastructure.Automations.EmailChannel do
  @moduledoc """
  ADR-346: `email` - an automatic message through the transactional outbox
  (ADR-203): the daily budget, suppressions, the per-kind unsubscribe of
  ADR-212 and the demo gate (ADR-184) all apply. Idempotent per delivery.
  """

  @behaviour Palee.Automations.Ports.Channel

  alias Palee.Email

  @transient [:throttled, :over_budget]

  @impl true
  def channel, do: "email"

  @impl true
  def reachable?(%{email: email}) when is_binary(email) and email != "", do: true
  def reachable?(_recipient), do: false

  @impl true
  def deliver(%{recipient: %{email: email} = recipient} = message) when is_binary(email) do
    case Email.enqueue(
           :box_automation,
           email,
           %{subject: message.subject, body: message.body, box_name: message.box_name},
           locale: recipient[:locale] || "en",
           organization_id: message.organization_id,
           user_id: recipient[:user_id],
           idempotency_key: "box_automation:" <> message.delivery_id
         ) do
      {:ok, sent} -> {:ok, sent.id}
      {:error, reason} when reason in @transient -> {:error, {:transient, reason}}
      {:error, reason} when is_atom(reason) -> {:error, {:permanent, reason}}
      {:error, _changeset} -> {:error, {:transient, :not_stored}}
    end
  end

  def deliver(_message), do: {:error, {:permanent, :no_email}}
end

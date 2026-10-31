defmodule Palee.Application.Integrations.WebhookEvents do
  @moduledoc """
  Feeds the box's webhooks from Palee's domain events (ADR-144, ADR-379).
  A domain event with a public form (`PublicEvents`) becomes one delivery
  per subscribed endpoint, written after the owner's change succeeded, and
  sending starts in the background. A box without webhooks costs one
  indexed read.
  """

  @behaviour Palee.DomainEvents.Handler

  alias Palee.Application.Integrations.WebhookDelivery
  alias Palee.Integrations
  alias Palee.Integrations.Domain.PublicEvents

  @impl true
  def handle_event(name, %{organization_id: organization_id} = payload)
      when is_binary(organization_id) do
    handle(name, payload, organization_id, DateTime.utc_now())
  end

  def handle_event(_name, _payload), do: :ok

  @doc false
  def handle(name, payload, organization_id, now) do
    with {:ok, type, data} <- PublicEvents.from_domain(name, payload) do
      context = %{organization_id: organization_id}
      at = PublicEvents.occurred_at(payload, now)

      case Integrations.enqueue_event(context, type, data, Ecto.UUID.generate(), at, now) do
        {:ok, 0} -> :ok
        {:ok, _count} -> WebhookDelivery.schedule(context)
      end
    else
      :ignore -> :ok
    end
  end
end

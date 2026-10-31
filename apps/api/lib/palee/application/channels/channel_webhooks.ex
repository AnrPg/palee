defmodule Palee.Application.Channels.ChannelWebhooks do
  @moduledoc """
  The messaging provider's calls on the box's webhook (ADR-348 §5):
  delivery receipts and inbound texts (STOP). The URL carries the box and
  a secret token; the provider's own signature is verified where it signs
  (Twilio). Nothing of an inbound text is stored except a STOP's effect.
  """

  alias Palee.Channels

  def handle(organization_id, token, request, now \\ DateTime.utc_now()) do
    case Ecto.UUID.cast(organization_id) do
      {:ok, organization_id} ->
        Channels.handle_webhook(%{organization_id: organization_id}, token, request, now)

      :error ->
        {:error, :not_found}
    end
  end
end

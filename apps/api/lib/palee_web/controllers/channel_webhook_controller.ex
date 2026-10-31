defmodule PaleeWeb.ChannelWebhookController do
  @moduledoc """
  ADR-348 §5: delivery receipts and replies from the box's messaging
  provider. The URL carries the box and a secret token; the provider's
  signature, where it signs, is checked over the raw body.
  """

  use PaleeWeb, :controller

  alias Palee.Application.Channels.ChannelWebhooks
  alias PaleeWeb.Plugs.CacheRawBody

  def create(conn, %{"organization_id" => organization_id, "token" => token} = params) do
    request = %{
      params: Map.drop(params, ["organization_id", "token"]),
      headers: conn.req_headers,
      raw_body: CacheRawBody.raw_body(conn)
    }

    case ChannelWebhooks.handle(organization_id, token, request) do
      {:ok, _counts} ->
        json(conn, %{ok: true})

      {:error, :invalid_signature} ->
        conn |> put_status(:unauthorized) |> json(%{code: "invalid_signature"})

      {:error, _reason} ->
        conn |> put_status(:not_found) |> json(%{code: "not_found"})
    end
  end
end

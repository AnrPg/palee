defmodule PaleeWeb.Plugs.AuthenticateApiKey do
  @moduledoc """
  The public API's authentication (ADR-378): `Authorization: Bearer
  palee_live_…`. Assigns the key holder's `tenant_context` (with the key as
  its `principal`) and names the key as the rate-limit actor, so each key
  has its own budget; otherwise answers 401 `invalid_api_key` with a
  `WWW-Authenticate` challenge. Keys of every box share this one door: the
  key says which box it is.
  """

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  alias Palee.Application.Integrations.PublicApi

  def init(opts), do: opts

  def call(conn, _opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, context} <- PublicApi.authenticate(String.trim(token), metadata(conn)) do
      conn
      |> assign(:tenant_context, context)
      |> assign(:rate_limit_actor, "api-key:" <> context.principal.api_key_id)
    else
      _missing_or_invalid ->
        conn
        |> put_resp_header("www-authenticate", ~s(Bearer realm="palee", error="invalid_token"))
        |> put_status(:unauthorized)
        |> json(%{
          code: "invalid_api_key",
          error: "Send a valid API key as Authorization: Bearer <key>"
        })
        |> halt()
    end
  end

  defp metadata(conn) do
    %{
      transport: :public_api,
      method: conn.method,
      request_id: List.first(get_resp_header(conn, "x-request-id"))
    }
  end
end

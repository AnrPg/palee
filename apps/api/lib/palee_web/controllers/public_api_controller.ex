defmodule PaleeWeb.PublicApiController do
  @moduledoc """
  The public API v1 (ADR-378). Every route is generated from the operation
  registry (ADR-300); the route carries its operation's name and this one
  action runs it through `PublicApi` (policy, schema, idempotency). Input
  is the path parameters plus the query (reads) or the JSON body
  (commands).

  Errors are problem details (`PaleeWeb.Plugs.ProblemDetails`) with the same
  stable codes as the rest of Palee.
  """

  use PaleeWeb, :controller

  alias Palee.Application.Integrations.PublicApi
  alias PaleeWeb.{FallbackController, PublicApiSpec}

  @doc false
  # Not in Palee's own OpenAPI document: the public API has its own.
  def open_api_operation(_action), do: nil

  def run(conn, _params) do
    name = conn.private.palee_operation
    opts = [idempotency_key: header(conn, "idempotency-key"), preview: preview?(conn)]

    case PublicApi.run(conn.assigns.tenant_context, name, input(conn), opts) do
      {:ok, status, body} -> respond(conn, status, body)
      {:ok, status, body, :replayed} -> conn |> put_resp_header("idempotent-replayed", "true") |> respond(status, body)
      error -> FallbackController.call(conn, error)
    end
  end

  @doc "`GET /api/public/v1/openapi.json`: the document, without a key."
  def openapi(conn, _params), do: json(conn, PublicApiSpec.document())

  defp respond(conn, 204, _body), do: send_resp(conn, 204, "")
  defp respond(conn, status, body), do: conn |> put_status(status) |> json(body)

  defp input(%{method: method} = conn) when method in ["POST", "PATCH", "PUT"],
    do: Map.merge(json_body(conn.body_params), conn.path_params)

  defp input(conn), do: Map.merge(conn.query_params, conn.path_params)

  # A JSON array or scalar body arrives under "_json"; operations take objects.
  defp json_body(%{"_json" => _not_an_object}), do: %{"_json" => nil}
  defp json_body(params), do: params

  defp header(conn, name), do: conn |> get_req_header(name) |> List.first()

  defp preview?(conn), do: header(conn, "palee-preview") in ["true", "1"]
end

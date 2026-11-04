defmodule PaleeWeb.Plugs.ProblemDetails do
  @moduledoc """
  The public API answers errors as RFC 9457 problem details (ADR-378):
  `application/problem+json` with `type`, `title`, `status`, plus Palee's
  stable `code` (and `params` or `errors` when there are any). It rewrites
  the regular `{code, error}` body just before sending, so every refusal
  (authentication, rate limits, domain errors from `FallbackController`)
  has the same form without a second error table.
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts), do: register_before_send(conn, &rewrite/1)

  @doc false
  def rewrite(%Plug.Conn{status: status} = conn) when is_integer(status) and status >= 400 do
    with true <- json?(conn),
         {:ok, %{"code" => code} = body} when is_binary(code) <-
           Jason.decode(IO.iodata_to_binary(conn.resp_body || "")) do
      problem =
        body
        |> Map.delete("error")
        |> Map.merge(%{
          "type" => "urn:palee:problem:" <> code,
          "title" => body["error"] || Plug.Conn.Status.reason_phrase(status),
          "status" => status
        })

      conn
      |> put_resp_content_type("application/problem+json")
      |> Map.put(:resp_body, Jason.encode!(problem))
    else
      _not_ours -> conn
    end
  end

  def rewrite(conn), do: conn

  defp json?(conn) do
    case get_resp_header(conn, "content-type") do
      [type | _rest] -> String.starts_with?(type, "application/json")
      [] -> false
    end
  end
end

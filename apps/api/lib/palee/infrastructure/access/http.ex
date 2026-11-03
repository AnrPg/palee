defmodule Palee.Infrastructure.Access.Http do
  @moduledoc """
  The HTTP call of the door adapters (ADR-381): short timeouts (a member is
  standing at the door), no retries, the outbound proxy and test plugs from
  `config :palee, :door_http, req_options: [...]`.
  """

  def request(options) do
    config = Application.get_env(:palee, :door_http, [])

    options
    |> Keyword.merge(
      receive_timeout: Keyword.get(config, :receive_timeout, 4_000),
      connect_options: [timeout: Keyword.get(config, :connect_timeout, 3_000)],
      retry: false
    )
    |> Keyword.merge(Keyword.get(config, :req_options, []))
    |> Req.request()
    |> case do
      {:ok, %Req.Response{status: status}} when status in [401, 403] ->
        {:error, {:unauthorized, {:http, status}}}

      {:ok, %Req.Response{status: status}} when status == 429 or status >= 500 ->
        {:error, {:offline, {:http, status}}}

      {:ok, %Req.Response{status: status} = response} when status in 200..299 ->
        {:ok, response}

      {:ok, %Req.Response{status: status}} ->
        {:error, {:rejected, {:http, status}}}

      {:error, exception} ->
        {:error, {:offline, Exception.message(exception)}}
    end
  end
end

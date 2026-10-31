defmodule Palee.Infrastructure.Integrations.AudienceHttp do
  @moduledoc """
  The HTTP call of the Mailchimp and Brevo adapters (ADR-380): proxy and
  test plugs from `config :palee, :audience_http, req_options: [...]`, no
  retries (the sync runs again), failures sorted for the port.
  """

  def request(options) do
    config = Application.get_env(:palee, :audience_http, [])

    options
    |> Keyword.merge(receive_timeout: Keyword.get(config, :receive_timeout, 15_000), retry: false)
    |> Keyword.merge(Keyword.get(config, :req_options, []))
    |> Req.request()
    |> case do
      {:ok, %Req.Response{status: status}} when status in [401, 403] ->
        {:error, {:unauthorized, {:http, status}}}

      {:ok, %Req.Response{status: status}} when status == 429 or status >= 500 ->
        {:error, {:transient, {:http, status}}}

      {:ok, %Req.Response{status: status} = response} when status in 200..299 ->
        {:ok, response}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:rejected, {:http, status, detail(body)}}}

      {:error, exception} ->
        {:error, {:transient, Exception.message(exception)}}
    end
  end

  # Mailchimp: `title`/`detail`; Brevo: `code`/`message`. Never the request.
  defp detail(%{"title" => title}), do: title
  defp detail(%{"code" => code}), do: code
  defp detail(_body), do: nil
end

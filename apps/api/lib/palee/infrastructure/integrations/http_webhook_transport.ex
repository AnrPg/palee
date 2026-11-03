defmodule Palee.Infrastructure.Integrations.HttpWebhookTransport do
  @moduledoc """
  Posts webhooks with Req (ADR-379): 10 s timeout, no redirects, no
  retries, at most 500 characters of the answer kept for the delivery log.

  Before connecting, the host is resolved and refused when any address is
  private, loopback or link-local (server-side request forgery). Test plugs
  (`config :palee, :webhook_http, req_options: [plug: ...]`) skip the DNS
  check, since no network is used.
  """

  @behaviour Palee.Integrations.Ports.WebhookTransport

  alias Palee.Integrations.Domain.EndpointUrl

  @excerpt 500

  @impl true
  def post(url, headers, body) do
    config = Application.get_env(:palee, :webhook_http, [])
    req_options = Keyword.get(config, :req_options, [])

    with :ok <- public_host(url, req_options) do
      [
        method: :post,
        url: url,
        headers: headers,
        body: body,
        receive_timeout: Keyword.get(config, :receive_timeout, 10_000),
        redirect: false,
        retry: false,
        decode_body: false
      ]
      |> Keyword.merge(req_options)
      |> Req.request()
      |> case do
        {:ok, %Req.Response{status: status, body: answer}} ->
          {:ok, %{status: status, body_excerpt: excerpt(answer)}}

        {:error, exception} ->
          {:error, Exception.message(exception)}
      end
    end
  end

  defp public_host(url, req_options) do
    if Keyword.has_key?(req_options, :plug) do
      :ok
    else
      host = URI.parse(url).host |> to_string() |> String.to_charlist()

      addresses =
        for family <- [:inet, :inet6],
            {:ok, list} <- [:inet.getaddrs(host, family)],
            address <- list,
            do: address

      cond do
        addresses == [] -> {:error, :nxdomain}
        Enum.any?(addresses, &EndpointUrl.private_address?/1) -> {:error, :blocked_address}
        true -> :ok
      end
    end
  end

  defp excerpt(body) when is_binary(body) do
    if String.valid?(body), do: String.slice(body, 0, @excerpt), else: nil
  end

  defp excerpt(_body), do: nil
end

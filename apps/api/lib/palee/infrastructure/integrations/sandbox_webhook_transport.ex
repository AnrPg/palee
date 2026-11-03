defmodule Palee.Infrastructure.Integrations.SandboxWebhookTransport do
  @moduledoc """
  Development webhooks (ADR-379): nothing leaves the machine. Every post is
  logged without its body and answered 200, so the delivery log, replay and
  retries can be tried locally. A URL whose path ends in `/fail` answers 500
  and one ending in `/gone` answers 410.
  """

  @behaviour Palee.Integrations.Ports.WebhookTransport

  require Logger

  @impl true
  def post(url, _headers, body) do
    Logger.info("sandbox_webhook url=#{url} bytes=#{byte_size(body)}")

    status =
      cond do
        String.ends_with?(url, "/fail") -> 500
        String.ends_with?(url, "/gone") -> 410
        true -> 200
      end

    {:ok, %{status: status, body_excerpt: "sandbox"}}
  end
end

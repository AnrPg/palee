defmodule Palee.Integrations.Ports.WebhookTransport do
  @moduledoc """
  Sends one signed webhook (ADR-379). The adapter posts the exact `body`
  with the given headers, follows no redirects, refuses hosts that resolve
  to private addresses (`{:error, :blocked_address}`) and answers within
  about ten seconds. It never retries: the outbox does.
  """

  @type result ::
          {:ok, %{status: integer(), body_excerpt: String.t() | nil}}
          | {:error, :blocked_address | term()}

  @callback post(url :: String.t(), headers :: [{String.t(), String.t()}], body :: binary()) ::
              result()
end

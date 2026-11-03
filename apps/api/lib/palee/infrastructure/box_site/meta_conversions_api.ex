defmodule Palee.Infrastructure.BoxSite.MetaConversionsApi do
  @moduledoc """
  ADR-354 §5: Meta's Conversions API (`POST /<pixel>/events` on the Graph
  API). The token travels as a form field and is never logged; failures
  are reported by status only.
  """

  @behaviour Palee.BoxSite.Ports.ConversionsApi

  @graph "https://graph.facebook.com/v21.0"

  @impl true
  def send_event(pixel_id, token, event) do
    config = Application.get_env(:palee, :box_site_http, [])

    [
      method: :post,
      url: "#{@graph}/#{pixel_id}/events",
      form: [data: Jason.encode!([event]), access_token: token],
      receive_timeout: 15_000,
      retry: false
    ]
    |> Keyword.merge(Keyword.get(config, :req_options, []))
    |> Req.request()
    |> case do
      {:ok, %Req.Response{status: status}} when status in 200..299 ->
        :ok

      {:ok, %Req.Response{status: status}} when status == 429 or status >= 500 ->
        {:error, {:transient, {:http, status}}}

      {:ok, %Req.Response{status: status}} ->
        {:error, {:rejected, {:http, status}}}

      {:error, _exception} ->
        {:error, {:transient, :unreachable}}
    end
  end
end

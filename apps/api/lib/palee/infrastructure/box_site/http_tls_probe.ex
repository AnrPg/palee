defmodule Palee.Infrastructure.BoxSite.HttpTlsProbe do
  @moduledoc """
  ADR-352 §6: a custom host is ready when `https://<host>` answers Palee's
  host lookup with a valid certificate (Req verifies it). Uses
  `config :palee, :box_site_http, req_options: [...]` (tests use Req.Test).
  """

  @behaviour Palee.BoxSite.Ports.TlsProbe

  @impl true
  def check(host) do
    config = Application.get_env(:palee, :box_site_http, [])

    [
      method: :get,
      url: "https://#{host}/api/public/sites/by-host/#{host}",
      receive_timeout: 10_000,
      retry: false,
      redirect: false
    ]
    |> Keyword.merge(Keyword.get(config, :req_options, []))
    |> Req.request()
    |> case do
      {:ok, %Req.Response{status: 200}} -> :ok
      {:ok, %Req.Response{status: status}} -> {:error, {:http, status}}
      {:error, %{reason: reason}} -> {:error, reason}
      {:error, _exception} -> {:error, :unreachable}
    end
  end
end

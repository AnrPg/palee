defmodule Palee.BoxSite.Ports.TlsProbe do
  @moduledoc """
  ADR-352 §6: whether `https://<host>` answers with a valid certificate and
  reaches Palee (`config :palee, :box_site_tls_probe`).
  """

  @callback check(host :: String.t()) :: :ok | {:error, term()}
end

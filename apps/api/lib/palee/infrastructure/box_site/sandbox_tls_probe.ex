defmodule Palee.Infrastructure.BoxSite.SandboxTlsProbe do
  @moduledoc """
  ADR-352: TLS readiness for dev and test: hosts listed in
  `config :palee, :box_site_sandbox_tls_ready` are ready.
  """

  @behaviour Palee.BoxSite.Ports.TlsProbe

  @impl true
  def check(host) do
    if host in Application.get_env(:palee, :box_site_sandbox_tls_ready, []),
      do: :ok,
      else: {:error, :sandbox_not_ready}
  end
end

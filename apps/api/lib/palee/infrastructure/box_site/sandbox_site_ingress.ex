defmodule Palee.Infrastructure.BoxSite.SandboxSiteIngress do
  @moduledoc """
  ADR-398: the cluster for dev and test. Every call succeeds and nothing is
  kept, except as configured:

    * `config :palee, :box_site_sandbox_ingress_refused, [host]`: refused;
    * `config :palee, :box_site_sandbox_certificates, %{host => :active | {:failed, reason}}`
      (default `:issuing`);
    * `config :palee, :box_site_sandbox_managed_hosts, [host]`: what the
      sweep finds.
  """

  @behaviour Palee.BoxSite.Ports.SiteIngress

  @impl true
  def apply_site(host), do: answer(host)

  @impl true
  def remove_site(host), do: answer(host)

  @impl true
  def certificate(host) do
    {:ok,
     Map.get(Application.get_env(:palee, :box_site_sandbox_certificates, %{}), host, :issuing)}
  end

  @impl true
  def managed_hosts, do: {:ok, Application.get_env(:palee, :box_site_sandbox_managed_hosts, [])}

  defp answer(host) do
    if host in Application.get_env(:palee, :box_site_sandbox_ingress_refused, []),
      do: {:error, {:refused, {:http, 403}}},
      else: :ok
  end
end

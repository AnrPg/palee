defmodule Palee.Application.BoxSite.SiteDomainChecks do
  @moduledoc """
  ADR-352 §5–6: checks a custom host (DNS proof, routing, then HTTPS) and
  moves it along its states. Run by «Έλεγχος τώρα», right after a host is
  added, and by `BoxSiteJob` for due hosts.
  """

  alias Palee.BoxSite

  @batch 20

  @doc "Checks one host now and saves the outcome."
  def check(context, domain, now) do
    dns = BoxSite.dns_facts(domain)

    tls_ok =
      if probe?(domain, dns), do: BoxSite.tls_probe().check(domain.host) == :ok, else: false

    changes = BoxSite.after_check(domain, Map.put(dns, :tls_ok, tls_ok), now)
    BoxSite.update_domain(context, domain.id, changes)
  end

  # TLS is probed only once DNS proves the host is the box's and points here.
  defp probe?(%{status: "pending_dns"}, %{txt_ok: txt, routing_ok: routing}), do: txt and routing
  defp probe?(_domain, %{routing_ok: routing}), do: routing

  @doc "Checks the box's due hosts."
  def run_due(context, now) do
    context
    |> BoxSite.due_domains(now, @batch)
    |> Enum.count(&match?({:ok, _}, check(context, &1, now)))
  end
end

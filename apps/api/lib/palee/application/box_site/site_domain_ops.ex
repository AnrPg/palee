defmodule Palee.Application.BoxSite.SiteDomainOps do
  @moduledoc """
  ADR-352 §6: the platform's list of custom hosts by state, for ops. Hosts
  in `pending_tls` need an Ingress (cert-manager HTTP-01) before they turn
  `active`; see `docs/operations/box-site-custom-domains.md`.
  """

  alias Palee.BoxSite

  @doc "Hosts in a state (default `pending_tls`)."
  def list(status) do
    status = status || "pending_tls"

    if status in BoxSite.domain_statuses(),
      do: {:ok, %{domains: BoxSite.domains_for_ops(status), cname_target: BoxSite.cname_target()}},
      else: {:error, :invalid_site_domain_status}
  end
end

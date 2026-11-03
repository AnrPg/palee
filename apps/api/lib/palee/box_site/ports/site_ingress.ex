defmodule Palee.BoxSite.Ports.SiteIngress do
  @moduledoc """
  ADR-398: the cluster side of a custom host. An adapter routes `host` to
  the box sites (an Ingress whose certificate cert-manager issues), removes
  that route, reads the certificate and lists the hosts it manages
  (`config :palee, :box_site_ingress`; `nil` turns automation off and the
  manual list of ADR-352 §6 stays the way).

  Errors are `{:transient, reason}` (retry soon) or `{:refused, reason}`
  (the cluster said no: RBAC, a missing kind; retried, but someone has to
  act).
  """

  @type error :: {:error, {:transient | :refused, term()}}
  @type certificate :: :issuing | :active | {:failed, atom()}

  @callback apply_site(host :: String.t()) :: :ok | error()
  @callback remove_site(host :: String.t()) :: :ok | error()
  @callback certificate(host :: String.t()) :: {:ok, certificate()} | error()
  @callback managed_hosts() :: {:ok, [String.t()]} | error()
end

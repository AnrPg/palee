defmodule Palee.BoxSite.Ports.DomainDns do
  @moduledoc """
  ADR-352 §5, ADR-398 (2026-11-03): DNS answers for a custom host's checks
  (`config :palee, :box_site_dns`).

  A lookup answers `{:ok, values}` (empty when the name has no such record or
  does not exist) or `{:error, reason}` when the resolver could not tell
  (timeout, SERVFAIL, unreachable): callers treat that as "unknown", never
  as "not pointing".
  """

  @type record_type :: :txt | :cname | :a | :aaaa

  @callback lookup(name :: String.t(), type :: record_type()) ::
              {:ok, [String.t()]} | {:error, term()}
end

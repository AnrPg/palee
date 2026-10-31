defmodule Palee.BoxSite.Ports.DomainDns do
  @moduledoc """
  ADR-352 §5: DNS answers for a custom host's checks (`config :palee,
  :box_site_dns`). Each lookup returns the record values (empty when there
  are none or the lookup failed).
  """

  @callback lookup(name :: String.t(), type :: :txt | :cname | :a) :: [String.t()]
end

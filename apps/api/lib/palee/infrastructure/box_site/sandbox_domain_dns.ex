defmodule Palee.Infrastructure.BoxSite.SandboxDomainDns do
  @moduledoc """
  ADR-352: DNS for dev and test. Answers come from
  `config :palee, :box_site_sandbox_dns, %{{name, type} => [values]}` (tests
  put them there); any other name answers nothing.
  """

  @behaviour Palee.BoxSite.Ports.DomainDns

  @impl true
  def lookup(name, type) do
    :palee
    |> Application.get_env(:box_site_sandbox_dns, %{})
    |> Map.get({name, type}, [])
  end
end

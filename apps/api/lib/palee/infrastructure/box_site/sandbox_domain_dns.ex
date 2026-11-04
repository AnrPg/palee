defmodule Palee.Infrastructure.BoxSite.SandboxDomainDns do
  @moduledoc """
  ADR-352: DNS for dev and test. Answers come from
  `config :palee, :box_site_sandbox_dns, %{{name, type} => [values] | {:error, reason}}`
  (tests put them there); any other name answers nothing, except the CNAME
  target's A record, which is `192.0.2.1` unless set (ADR-398: the check
  resolves the target's addresses live).
  """

  @behaviour Palee.BoxSite.Ports.DomainDns

  @target_address "192.0.2.1"

  @doc "The address the sandbox gives the CNAME target unless a test sets one."
  def target_address, do: @target_address

  @impl true
  def lookup(name, type) do
    answers = Application.get_env(:palee, :box_site_sandbox_dns, %{})

    case Map.get(answers, {name, type}, default(name, type)) do
      {:error, _reason} = error -> error
      values when is_list(values) -> {:ok, values}
    end
  end

  defp default(name, :a) do
    target = :palee |> Application.get_env(:box_site, []) |> Keyword.get(:cname_target)
    if name == target, do: [@target_address], else: []
  end

  defp default(_name, _type), do: []
end

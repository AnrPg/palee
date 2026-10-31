defmodule Palee.Infrastructure.BoxSite.InetDomainDns do
  @moduledoc "ADR-352: DNS lookups for custom hosts through Erlang's resolver."

  @behaviour Palee.BoxSite.Ports.DomainDns

  @timeout 5_000

  @impl true
  def lookup(name, type) when type in [:txt, :cname, :a] do
    name
    |> String.to_charlist()
    |> :inet_res.lookup(:in, type, timeout: @timeout)
    |> Enum.map(&format(type, &1))
  rescue
    _error -> []
  end

  defp format(:txt, chunks), do: chunks |> Enum.map(&to_string/1) |> Enum.join()
  defp format(:cname, name), do: to_string(name)
  defp format(:a, ip), do: ip |> :inet.ntoa() |> to_string()
end

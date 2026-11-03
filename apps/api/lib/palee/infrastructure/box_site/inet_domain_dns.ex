defmodule Palee.Infrastructure.BoxSite.InetDomainDns do
  @moduledoc """
  ADR-352, ADR-398: DNS lookups for custom hosts through Erlang's resolver.
  A missing name (NXDOMAIN) or a name without such records is `{:ok, []}`;
  a timeout or a failing server is `{:error, reason}` (unknown).
  """

  @behaviour Palee.BoxSite.Ports.DomainDns

  @timeout 5_000

  @impl true
  def lookup(name, type) when type in [:txt, :cname, :a, :aaaa] do
    name
    |> String.to_charlist()
    |> :inet_res.resolve(:in, type, timeout: @timeout)
    |> answers(type)
  rescue
    _error -> {:error, :resolver_crashed}
  end

  defp answers({:ok, message}, type) do
    {:ok,
     message
     |> :inet_dns.msg(:anlist)
     |> Enum.filter(&(:inet_dns.rr(&1, :type) == type))
     |> Enum.map(&format(type, :inet_dns.rr(&1, :data)))}
  end

  defp answers({:error, :nxdomain}, _type), do: {:ok, []}
  defp answers({:error, {:nxdomain, _message}}, _type), do: {:ok, []}
  defp answers({:error, {reason, _message}}, _type), do: {:error, reason}
  defp answers({:error, reason}, _type), do: {:error, reason}

  defp format(:txt, chunks), do: chunks |> Enum.map(&to_string/1) |> Enum.join()
  defp format(:cname, name), do: to_string(name)
  defp format(_address, ip), do: ip |> :inet.ntoa() |> to_string()
end

defmodule Palee.BoxSite.Domain.Hostname do
  @moduledoc """
  ADR-352 §5: a custom host a box may claim. Lower case, no trailing dot,
  at least two labels, no IP addresses and none of the platform's own
  domains: the system domains below (the cluster's tenant policy refuses or
  reserves them, ADR-398 2026-11-03) and `refused_suffixes` from config.
  """

  @system_suffixes ~w(palee.app 4kq.net atha.gr atha.io)

  @doc "Domains no box may claim, nor any name under them."
  def system_suffixes, do: @system_suffixes

  @label ~r/^(?!-)[a-z0-9-]{1,63}(?<!-)$/
  @ipv4 ~r/^\d{1,3}(\.\d{1,3}){3}$/

  @doc "`{:ok, host}` or `{:error, :invalid_hostname | :platform_hostname}`."
  def normalize(host, refused_suffixes) when is_binary(host) do
    host =
      host
      |> String.trim()
      |> String.downcase()
      |> String.replace_prefix("https://", "")
      |> String.replace_prefix("http://", "")
      |> String.trim_trailing("/")
      |> String.trim_trailing(".")

    labels = String.split(host, ".")

    cond do
      byte_size(host) > 253 or length(labels) < 2 -> {:error, :invalid_hostname}
      Regex.match?(@ipv4, host) or String.contains?(host, ":") -> {:error, :invalid_hostname}
      not Enum.all?(labels, &Regex.match?(@label, &1)) -> {:error, :invalid_hostname}
      Regex.match?(~r/^[0-9]+$/, List.last(labels)) -> {:error, :invalid_hostname}
      platform?(host, @system_suffixes ++ refused_suffixes) -> {:error, :platform_hostname}
      true -> {:ok, host}
    end
  end

  def normalize(_host, _refused), do: {:error, :invalid_hostname}

  defp platform?(host, suffixes) do
    Enum.any?(suffixes, fn suffix ->
      suffix = String.downcase(suffix)
      host == suffix or String.ends_with?(host, "." <> suffix)
    end)
  end

  @doc "An apex host (two labels, or a known two-part public suffix) cannot use a CNAME."
  def apex?(host) do
    labels = String.split(host, ".")

    case labels do
      [_name, _tld] -> true
      [_name, second, tld] -> "#{second}.#{tld}" in ~w(com.gr co.uk com.cy com.au org.uk)
      _deeper -> false
    end
  end
end

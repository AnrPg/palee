defmodule Palee.Integrations.Domain.EndpointUrl do
  @moduledoc """
  Where a webhook may be sent (ADR-379): an absolute `https://` URL of a
  public host, up to 2000 characters, without credentials in it. Literal
  private, loopback and link-local addresses and `localhost` are refused
  here; the HTTP adapter also refuses a host whose DNS answer is private
  (server-side request forgery, OWASP A10), so a box cannot make Palee call
  its own network.

  `allow_http` and `allow_private` are for development only (config), never
  in production.
  """

  @max_length 2000

  @spec validate(term(), keyword()) :: {:ok, String.t()} | {:error, :invalid_webhook_url}
  def validate(url, opts \\ [])

  def validate(url, opts) when is_binary(url) do
    url = String.trim(url)
    allowed_schemes = if Keyword.get(opts, :allow_http, false), do: ~w(https http), else: ~w(https)

    with true <- byte_size(url) <= @max_length,
         %URI{scheme: scheme, host: host, userinfo: nil} when is_binary(host) and host != "" <-
           URI.parse(url),
         true <- scheme in allowed_schemes,
         false <- private_host?(host) and not Keyword.get(opts, :allow_private, false) do
      {:ok, url}
    else
      _invalid -> {:error, :invalid_webhook_url}
    end
  end

  def validate(_url, _opts), do: {:error, :invalid_webhook_url}

  @doc "Whether a host name or literal address is not a public internet address."
  def private_host?(host) when is_binary(host) do
    host = host |> String.trim_leading("[") |> String.trim_trailing("]") |> String.downcase()

    cond do
      host in ["localhost", "localhost.localdomain"] -> true
      String.ends_with?(host, ".localhost") or String.ends_with?(host, ".local") -> true
      String.ends_with?(host, ".internal") -> true
      true -> host |> String.to_charlist() |> :inet.parse_address() |> private_address?()
    end
  end

  @doc "Whether an `:inet` address tuple is private, loopback, link-local or reserved."
  def private_address?({:ok, address}), do: private_address?(address)
  def private_address?({:error, _not_an_address}), do: false
  def private_address?({10, _, _, _}), do: true
  def private_address?({127, _, _, _}), do: true
  def private_address?({0, _, _, _}), do: true
  def private_address?({169, 254, _, _}), do: true
  def private_address?({172, second, _, _}) when second in 16..31, do: true
  def private_address?({192, 168, _, _}), do: true
  def private_address?({100, second, _, _}) when second in 64..127, do: true
  def private_address?({a, _, _, _}) when a >= 224, do: true
  def private_address?({0, 0, 0, 0, 0, 0, 0, 0}), do: true
  def private_address?({0, 0, 0, 0, 0, 0, 0, 1}), do: true
  def private_address?({0, 0, 0, 0, 0, 0xFFFF, a, b}),
    do: private_address?({div(a, 256), rem(a, 256), div(b, 256), rem(b, 256)})

  def private_address?({first, _, _, _, _, _, _, _}) when first in 0xFC00..0xFDFF, do: true
  def private_address?({first, _, _, _, _, _, _, _}) when first in 0xFE80..0xFEBF, do: true
  def private_address?({first, _, _, _, _, _, _, _}) when first >= 0xFF00, do: true
  def private_address?(_address), do: false
end

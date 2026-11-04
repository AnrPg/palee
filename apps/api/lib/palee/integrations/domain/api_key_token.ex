defmodule Palee.Integrations.Domain.ApiKeyToken do
  @moduledoc """
  The shape of a public API key (ADR-378):

      palee_<env>_<prefix>_<secret>

  `env` is `live` or `test` (a sandbox box), `prefix` 12 base32 characters
  that name the key in lists and logs and find its box, and `secret` 40
  base32 characters (200 bits). Only `prefix` and the SHA-256 of the whole
  token are stored: a high-entropy random token needs no slow hash, and a
  database dump cannot be turned back into keys.

  Pure: randomness comes in as bytes.
  """

  @alphabet ~c"abcdefghijklmnopqrstuvwxyz234567"
  @prefix_length 12
  @secret_length 40
  @envs ~w(live test)

  @type t :: %{token: String.t(), prefix: String.t(), hash: binary()}

  @doc "Bytes `new/2` needs: one per character of prefix and secret."
  def random_bytes_needed, do: @prefix_length + @secret_length

  @doc "A new token from `random_bytes_needed/0` random bytes."
  @spec new(String.t(), binary()) :: t()
  def new(env, random) when env in @envs and byte_size(random) == 52 do
    chars = for <<byte <- random>>, into: "", do: <<Enum.at(@alphabet, rem(byte, 32))>>
    <<prefix::binary-size(@prefix_length), secret::binary-size(@secret_length)>> = chars
    token = "palee_#{env}_#{prefix}_#{secret}"
    %{token: token, prefix: prefix, hash: hash(token)}
  end

  @doc "`{:ok, prefix}` for a well-formed token, otherwise `:error`."
  def parse("palee_" <> rest) do
    case String.split(rest, "_") do
      [env, prefix, secret]
      when env in @envs and byte_size(prefix) == @prefix_length and
             byte_size(secret) == @secret_length ->
        if base32?(prefix) and base32?(secret), do: {:ok, prefix}, else: :error

      _other ->
        :error
    end
  end

  def parse(_token), do: :error

  @doc "SHA-256 of the whole token."
  def hash(token) when is_binary(token), do: :crypto.hash(:sha256, token)

  @doc "Constant-time check of `token` against a stored hash (nil never matches)."
  def matches?(token, hash) when is_binary(token) and is_binary(hash),
    do: byte_size(hash) == 32 and :crypto.hash_equals(hash(token), hash)

  def matches?(_token, _hash), do: false

  @doc "What a list shows instead of the key: `palee_live_<prefix>_…`."
  def masked(env, prefix), do: "palee_#{env}_#{prefix}_…"

  defp base32?(value), do: value |> String.to_charlist() |> Enum.all?(&(&1 in @alphabet))
end

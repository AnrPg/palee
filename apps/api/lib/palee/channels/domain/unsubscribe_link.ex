defmodule Palee.Channels.Domain.UnsubscribeLink do
  @moduledoc """
  The short signed link at the end of a marketing SMS (ADR-390). An
  alphanumeric sender («BoxKypseli») cannot receive a STOP reply, so the
  person taps the link instead; it withdraws their marketing SMS consent
  at that box.

  The token names the contact only and is signed, so it can be neither
  guessed nor changed to another person:

      contact id (16 bytes) | HMAC-SHA256 (first #{6} bytes)

  url-safe base64 without padding: 30 characters. The contact's box is
  found from the contact once the signature is checked. The key is derived
  from the channels key for this one purpose, and the link does not
  expire, because a person may tap it in an old message.

  Pure: callers bring the key and the base URL.
  """

  @mac_bytes 6
  @id_bytes 16
  @path "/u/"

  @doc "The token of a contact."
  @spec sign(binary(), Ecto.UUID.t()) :: String.t()
  def sign(key, contact_id) do
    raw = Ecto.UUID.dump!(contact_id)
    Base.url_encode64(raw <> mac(key, raw), padding: false)
  end

  @doc "`{:ok, contact_id}` for a token `key` signed, else `:error`."
  @spec verify(binary(), term()) :: {:ok, Ecto.UUID.t()} | :error
  def verify(key, token) when is_binary(token) and byte_size(token) <= 64 do
    with {:ok, <<raw::binary-size(@id_bytes), given::binary-size(@mac_bytes)>>} <-
           Base.url_decode64(token, padding: false),
         true <- Base.url_encode64(raw <> given, padding: false) == token,
         true <- Plug.Crypto.secure_compare(mac(key, raw), given) do
      Ecto.UUID.load(raw)
    else
      _invalid -> :error
    end
  end

  def verify(_key, _token), do: :error

  @doc """
  The link as the SMS shows it: the app's host without `https://` (phones
  make it a link and it costs fewer characters), `/u/` and the token.
  """
  @spec url(String.t(), String.t()) :: String.t()
  def url(base_url, token) do
    base_url
    |> String.trim_trailing("/")
    |> String.replace_prefix("https://", "")
    |> Kernel.<>(@path <> token)
  end

  @doc "The signing key for these links, derived from the channels key."
  @spec derive_key(binary()) :: binary()
  def derive_key(secret), do: :crypto.mac(:hmac, :sha256, secret, "channel-unsubscribe-link")

  defp mac(key, payload),
    do: :hmac |> :crypto.mac(:sha256, key, payload) |> binary_part(0, @mac_bytes)
end

defmodule Palee.Status.Domain.SubscriberPolicy do
  @moduledoc """
  Email subscriptions to status updates (ADR-364).

  * **Double opt-in.** A request stores the address with the digest of a
    one-time confirmation token and sends the token by email; nothing else
    is sent until it is confirmed. An unconfirmed request is deleted after
    `confirm_hours/0` hours.
  * **Data minimisation.** Only the address, its language and when it was
    confirmed are kept. Unsubscribing deletes the row.
  * **No enumeration.** The public answer is the same whether the address
    is new, waiting or already confirmed.
  * **Unsubscribe links** are signed tokens over the subscriber id, made by
    the caller with the platform's signer: nothing to store, and a link
    stops working once the row is gone.

  Pure: callers pass tokens and `now`.
  """

  @confirm_hours 48
  @locales ~w(ar bg de el en es fr he it nl pt_PT ru)

  def confirm_hours, do: @confirm_hours
  def locales, do: @locales

  @doc "Normalises and checks an address: `{:ok, email}` or `{:error, :invalid_email}`."
  def normalize_email(email) when is_binary(email) do
    email = email |> String.trim() |> String.downcase()

    if String.length(email) in 3..254 and
         Regex.match?(~r/^[^\s@<>()",;:]+@[^\s@<>()",;:]+\.[^\s@<>()",;:]+$/u, email),
       do: {:ok, email},
       else: {:error, :invalid_email}
  end

  def normalize_email(_email), do: {:error, :invalid_email}

  @doc "A supported locale (the region part is kept for `pt_PT`), `en` otherwise."
  def locale(locale) when is_binary(locale) do
    normalized = String.replace(locale, "-", "_")
    base = normalized |> String.split("_") |> hd() |> String.downcase()

    cond do
      normalized in @locales -> normalized
      base == "pt" -> "pt_PT"
      base in @locales -> base
      true -> "en"
    end
  end

  def locale(_locale), do: "en"

  @doc "The stored digest of an address or a token (lower-case hex SHA-256)."
  def digest(value) when is_binary(value),
    do: :sha256 |> :crypto.hash(value) |> Base.encode16(case: :lower)

  @doc "Whether an unconfirmed request (made or renewed at `updated_at`) has expired."
  def expired?(%{confirmed_at: nil, updated_at: updated_at}, %DateTime{} = now),
    do: DateTime.diff(now, updated_at) > @confirm_hours * 3600

  def expired?(_subscriber, _now), do: false

  @doc "The cut-off: an unconfirmed request made or renewed before it has expired."
  def unconfirmed_before(%DateTime{} = now), do: DateTime.add(now, -@confirm_hours * 3600)

  @doc """
  What a new request does to an existing row: a confirmed subscriber is
  left as it is (`:already_confirmed`); a waiting one gets a fresh token
  (`:refresh`); no row is created (`:create`).
  """
  def on_request(nil), do: :create
  def on_request(%{confirmed_at: nil}), do: :refresh
  def on_request(_confirmed), do: :already_confirmed
end

defmodule Palee.Integrations.Domain.WebhookSignature do
  @moduledoc """
  The signature on every webhook Palee sends (ADR-379), in the style
  receivers already know from Stripe and Standard Webhooks:

      Palee-Signature: t=1767225600,v1=<hex HMAC-SHA256(secret, "<t>.<body>")>

  The timestamp is signed with the body, so a receiver that rejects old
  timestamps (5 minutes is the default here) is safe from replays. While a
  secret is being rotated both the new and the previous secret sign, each as
  its own `v1=` entry, and a receiver accepts any.

  Pure: the time comes in as unix seconds.
  """

  @header "palee-signature"
  @tolerance_seconds 300

  def header_name, do: @header
  def tolerance_seconds, do: @tolerance_seconds

  @doc "The header value for `body`, signed with each of `secrets` (first is current)."
  @spec header([binary()], integer(), binary()) :: String.t()
  def header(secrets, timestamp, body)
      when is_list(secrets) and secrets != [] and is_integer(timestamp) and is_binary(body) do
    signatures = Enum.map(secrets, &"v1=#{sign(&1, timestamp, body)}")
    Enum.join(["t=#{timestamp}" | signatures], ",")
  end

  @doc "Lower-case hex HMAC-SHA256 of `<timestamp>.<body>`."
  def sign(secret, timestamp, body) when is_binary(secret) do
    :hmac
    |> :crypto.mac(:sha256, secret, "#{timestamp}.#{body}")
    |> Base.encode16(case: :lower)
  end

  @doc """
  What a receiver does (and what the docs and tests show): `:ok` when one
  `v1` matches and the timestamp is within the tolerance of `now`.
  """
  @spec verify(binary(), String.t(), binary(), integer(), pos_integer()) ::
          :ok | {:error, :malformed | :stale | :mismatch}
  def verify(secret, header, body, now, tolerance \\ @tolerance_seconds)
      when is_binary(header) and is_integer(now) do
    with {:ok, timestamp, signatures} <- parse(header),
         :ok <- fresh(timestamp, now, tolerance) do
      expected = sign(secret, timestamp, body)

      if Enum.any?(
           signatures,
           &(byte_size(&1) == byte_size(expected) and :crypto.hash_equals(&1, expected))
         ),
         do: :ok,
         else: {:error, :mismatch}
    end
  end

  defp parse(header) do
    pairs =
      header
      |> String.split(",")
      |> Enum.map(&String.split(String.trim(&1), "=", parts: 2))

    timestamp =
      Enum.find_value(pairs, fn
        ["t", value] -> parse_int(value)
        _other -> nil
      end)

    signatures = for ["v1", value] <- pairs, do: value

    if is_integer(timestamp) and signatures != [],
      do: {:ok, timestamp, signatures},
      else: {:error, :malformed}
  end

  defp parse_int(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _other -> nil
    end
  end

  defp fresh(timestamp, now, tolerance) do
    if abs(now - timestamp) <= tolerance, do: :ok, else: {:error, :stale}
  end
end

defmodule Palee.Integrations.Domain.Idempotency do
  @moduledoc """
  ADR-300 §5's `Idempotency-Key`, the general form of what online payments
  already do: the first answer to a command is kept for #{24} hours, and the
  same key with the same request gets that answer again without running the
  command twice. The same key with a different request is a client bug and
  is refused; a key whose first request is still running answers 409.

  Pure: the request fingerprint is a hash of the operation and its input
  in a canonical form (map keys sorted), so key order in JSON does not
  matter.
  """

  @ttl_hours 24
  @max_length 255

  def ttl_hours, do: @ttl_hours

  @doc "`{:ok, key}` for 1–255 visible ASCII characters, otherwise `{:error, :invalid_idempotency_key}`."
  def validate_key(key) when is_binary(key) do
    if byte_size(key) in 1..@max_length and key =~ ~r/\A[\x21-\x7E]+\z/,
      do: {:ok, key},
      else: {:error, :invalid_idempotency_key}
  end

  def validate_key(_key), do: {:error, :invalid_idempotency_key}

  @doc "Hex SHA-256 of the operation and its input."
  def fingerprint(operation, input) do
    :sha256
    |> :crypto.hash([operation, 0, canonical(input)])
    |> Base.encode16(case: :lower)
  end

  def expires_at(%DateTime{} = now), do: DateTime.add(now, @ttl_hours * 3_600, :second)

  @doc """
  What to do with a stored record for the same key: `{:replay, status,
  body}`, `{:error, :idempotency_key_in_use}` (still running) or
  `{:error, :idempotency_key_reused}` (another request).
  """
  def decide(%{request_hash: hash} = record, hash) do
    case record do
      %{state: "completed", response_status: status, response_body: body} ->
        {:replay, status, body}

      _running ->
        {:error, :idempotency_key_in_use}
    end
  end

  def decide(_record, _other_hash), do: {:error, :idempotency_key_reused}

  defp canonical(value) when is_map(value) do
    inner =
      value
      |> Enum.map(fn {key, item} -> {to_string(key), item} end)
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(fn {key, item} -> [Jason.encode!(key), ":", canonical(item)] end)
      |> Enum.intersperse(",")

    ["{", inner, "}"]
  end

  defp canonical(value) when is_list(value),
    do: ["[", value |> Enum.map(&canonical/1) |> Enum.intersperse(","), "]"]

  defp canonical(value) when is_atom(value) and value not in [nil, true, false],
    do: Jason.encode!(Atom.to_string(value))

  defp canonical(value), do: Jason.encode!(value)
end

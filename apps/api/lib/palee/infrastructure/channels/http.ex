defmodule Palee.Infrastructure.Channels.Http do
  @moduledoc """
  The HTTP call shared by the channel adapters (ADR-348): honours the
  outbound proxy and test plugs (`config :palee, :channels_http,
  req_options: [...]`), never retries by itself (the outbox does), and
  sorts failures into what `Channels.Ports.MessagingChannel` understands.
  A request that may have reached the provider (a timeout, a dropped
  connection) is `:uncertain`.
  """

  @safe_reasons [:econnrefused, :nxdomain, :ehostunreach, :enetunreach, :eaddrnotavail]

  def request(options) do
    config = Application.get_env(:palee, :channels_http, [])

    options
    |> Keyword.merge(receive_timeout: Keyword.get(config, :receive_timeout, 15_000), retry: false)
    |> Keyword.merge(Keyword.get(config, :req_options, []))
    |> Req.request()
    |> case do
      {:ok, %Req.Response{} = response} ->
        classify(response)

      {:error, %Req.TransportError{reason: reason}} when reason in @safe_reasons ->
        {:error, {:transient, reason}}

      {:error, exception} ->
        {:error, {:uncertain, Exception.message(exception)}}
    end
  end

  defp classify(%Req.Response{status: status}) when status in [401, 403],
    do: {:error, {:unauthorized, {:http, status}}}

  defp classify(%Req.Response{status: status}) when status == 429 or status >= 500,
    do: {:error, {:transient, {:http, status}}}

  defp classify(%Req.Response{status: status} = response) when status in 200..299,
    do: {:ok, response}

  defp classify(%Req.Response{status: status, body: body}),
    do: {:error, {:rejected, {:http, status, error_text(body)}}}

  defp error_text(%{} = body),
    do:
      body
      |> Map.take(["code", "message", "requestError", "error"])
      |> inspect()
      |> String.slice(0, 300)

  defp error_text(body) when is_binary(body), do: String.slice(body, 0, 300)
  defp error_text(_body), do: nil

  @doc "Cents from a decimal amount as a provider writes it; negative prices count as cost."
  def cents(nil), do: nil
  def cents(amount) when is_integer(amount), do: abs(amount) * 100
  def cents(amount) when is_float(amount), do: amount |> Decimal.from_float() |> to_cents()

  def cents(amount) when is_binary(amount) do
    case Decimal.parse(amount) do
      {decimal, ""} -> to_cents(decimal)
      _other -> nil
    end
  end

  def cents(_amount), do: nil

  defp to_cents(decimal),
    do: decimal |> Decimal.abs() |> Decimal.mult(100) |> Decimal.round(0, :ceiling) |> Decimal.to_integer()

  def header(headers, name) do
    Enum.find_value(headers, fn {key, value} ->
      if String.downcase(key) == name, do: value
    end)
  end

  @doc "Constant-time comparison of two strings."
  def secure_equal?(a, b) when is_binary(a) and is_binary(b) and byte_size(a) == byte_size(b),
    do: Plug.Crypto.secure_compare(a, b)

  def secure_equal?(_a, _b), do: false
end

defmodule Palee.Infrastructure.Channels.SandboxChannel do
  @moduledoc """
  The sandbox provider (ADR-348 §3): nothing leaves Palee. Used in
  development, tests and by demo boxes. A number ending in `000` is
  refused, one ending in `999` meets a provider outage; anything else is
  accepted. A secret `bad` fails «Δοκιμή σύνδεσης».

  Its webhook takes JSON `{"message_id", "status", "error_code"}` (a
  receipt) or `{"channel", "from", "text"}` (an inbound text), signed with
  `x-palee-signature`: the hex HMAC-SHA256 of the raw body keyed with the
  connection's secret (or `sandbox`).
  """

  @behaviour Palee.Channels.Ports.MessagingChannel

  alias Palee.Infrastructure.Channels.Http

  @impl true
  def channels, do: ~w(sms viber whatsapp)

  @impl true
  def send_message(_account, %{to: to, id: id}) do
    cond do
      String.ends_with?(to, "000") -> {:error, {:rejected, "sandbox_rejected_number"}}
      String.ends_with?(to, "999") -> {:error, {:transient, "sandbox_outage"}}
      true -> {:ok, %{provider_message_id: "sbx_" <> id, cost_cents: nil, currency: nil}}
    end
  end

  @impl true
  def check(%{secret: "bad"}), do: {:error, {:unauthorized, "sandbox_bad_secret"}}
  def check(_account), do: {:ok, %{balance: nil}}

  @impl true
  def parse_webhook(account, %{raw_body: raw_body, headers: headers, params: params}) do
    expected = signature(account, raw_body)

    if Http.secure_equal?(Http.header(headers, "x-palee-signature") || "", expected),
      do: {:ok, events(params)},
      else: {:error, :invalid_signature}
  end

  @doc "The signature the sandbox webhook expects (tests and local tools)."
  def signature(account, raw_body),
    do:
      :hmac
      |> :crypto.mac(:sha256, account[:secret] || "sandbox", raw_body)
      |> Base.encode16(case: :lower)

  defp events(%{"message_id" => id, "status" => status} = params) when is_binary(id) do
    [
      %{
        type: :status,
        provider_message_id: id,
        status: status(status),
        provider_status: status,
        error_code: params["error_code"],
        cost_cents: params["cost_cents"],
        currency: params["currency"],
        occurred_at: nil,
        event_key: "sandbox:#{id}:#{status}"
      }
    ]
  end

  defp events(%{"from" => from, "text" => text} = params) when is_binary(from),
    do: [%{type: :inbound, channel: params["channel"] || "sms", from: from, text: text}]

  defp events(_params), do: []

  defp status("delivered"), do: "delivered"
  defp status("failed"), do: "failed"
  defp status(_other), do: "sent"
end

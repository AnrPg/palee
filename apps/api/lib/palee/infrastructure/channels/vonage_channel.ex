defmodule Palee.Infrastructure.Channels.VonageChannel do
  @moduledoc """
  Vonage SMS API, a box's own account (ADR-396). SMS only.

    * send: `POST https://rest.nexmo.com/sms/json`, form fields `api_key`,
      `api_secret`, `from` (a name of up to 11 characters or a number),
      `to` (digits with the country code), `text`, `type` (`unicode` for
      texts outside the GSM alphabet, Greek), `callback` (the box's webhook
      URL for this message's receipt) and `client-ref` (the message id).
      Vonage answers 200 with a `status` per message part: `0` is accepted;
    * check: `GET https://rest.nexmo.com/account/get-balance` (basic auth);
    * webhook: delivery receipts (`messageId`, `status` `delivered`,
      `expired`, `failed`, `rejected`, `accepted`, `buffered`, `unknown`,
      `err-code`) and inbound texts (`msisdn`, `text`), by GET or POST.
      When the box saved Vonage's signature secret (`webhook_secret`; Vonage
      support switches signed webhooks on) the `sig` parameter must match:
      every other parameter sorted by name as `&name=value` (`&` and `=` in
      values become `_`), then MD5 with the secret appended (`md5hash`) or
      an HMAC (MD5, SHA-1, SHA-256 or SHA-512, told apart by length) keyed
      with it, in hex. Without the secret the box's URL token is the
      authentication, and a receipt must name a message of this box.

  Errors (`status`): 1 throttled and 5 internal error are retried, 9 (no
  balance) waits like Brevo's missing credits, 4 and 14 are refused
  credentials, everything else refuses that message (`vonage_<status>`).
  Vonage bills in the account's currency, not told per message, so the
  outbox keeps its own estimate.

  https://developer.vonage.com/en/api/sms
  https://developer.vonage.com/en/messaging/sms/guides/delivery-receipts
  https://developer.vonage.com/en/messaging/sms/guides/troubleshooting-sms
  https://developer.vonage.com/en/getting-started/concepts/signing-messages
  https://developer.vonage.com/en/api/account
  """

  @behaviour Palee.Channels.Ports.MessagingChannel

  alias Palee.Channels.Domain.MessageText
  alias Palee.Infrastructure.Channels.Http

  @default_base_url "https://rest.nexmo.com"

  @impl true
  def channels, do: ["sms"]

  @impl true
  def send_message(%{account_id: key, secret: secret} = account, %{channel: "sms"} = outgoing)
      when is_binary(key) and is_binary(secret) do
    case account[:sms_sender] do
      sender when is_binary(sender) and sender != "" ->
        form =
          [
            {"api_key", key},
            {"api_secret", secret},
            {"from", String.trim_leading(sender, "+")},
            {"to", String.trim_leading(outgoing.to, "+")},
            {"text", outgoing.body},
            {"type", if(MessageText.encoding(outgoing.body) == :ucs2, do: "unicode", else: "text")},
            {"client-ref", outgoing.id}
          ] ++ callback(outgoing)

        [method: :post, url: base_url() <> "/sms/json", form: form]
        |> Http.request()
        |> accepted()

      _missing ->
        {:error, {:rejected, "sms_sender_missing"}}
    end
  end

  def send_message(%{account_id: key, secret: secret}, %{channel: channel})
      when is_binary(key) and is_binary(secret),
      do: {:error, {:rejected, "channel_not_supported:" <> channel}}

  def send_message(_account, _outgoing),
    do: {:error, {:unauthorized, "vonage_credentials_missing"}}

  defp callback(%{callback_url: url}) when is_binary(url), do: [{"callback", url}]
  defp callback(_outgoing), do: []

  defp accepted({:ok, %{body: %{"messages" => [_first | _rest] = parts}}}) do
    case Enum.find(parts, &(&1["status"] != "0")) do
      nil ->
        {:ok, %{provider_message_id: hd(parts)["message-id"], cost_cents: nil, currency: nil}}

      %{"status" => status} ->
        {:error, status_error(status)}
    end
  end

  defp accepted({:ok, _unexpected}), do: {:error, {:uncertain, "vonage_unexpected_answer"}}
  defp accepted({:error, {kind, {:http, status}}}), do: {:error, {kind, "vonage_http_#{status}"}}

  defp accepted({:error, {:rejected, {:http, status, _detail}}}),
    do: {:error, {:rejected, "vonage_http_#{status}"}}

  defp accepted({:error, error}), do: {:error, error}

  @doc false
  def status_error(status) when status in ["1", "5"], do: {:transient, "vonage_" <> status}
  def status_error("9"), do: {:transient, "vonage_9"}
  def status_error(status) when status in ["4", "14"], do: {:unauthorized, "vonage_" <> status}
  def status_error(status) when is_binary(status), do: {:rejected, "vonage_" <> status}
  def status_error(_status), do: {:rejected, "vonage_rejected"}

  @impl true
  def check(%{account_id: key, secret: secret}) when is_binary(key) and is_binary(secret) do
    case Http.request(
           method: :get,
           url: base_url() <> "/account/get-balance",
           auth: {:basic, "#{key}:#{secret}"}
         ) do
      {:ok, %{body: %{"value" => value}}} -> {:ok, %{balance: value}}
      {:ok, _other} -> {:ok, %{balance: nil}}
      {:error, {kind, {:http, status}}} -> {:error, {kind, "vonage_http_#{status}"}}
      {:error, {kind, {:http, status, _detail}}} -> {:error, {kind, "vonage_http_#{status}"}}
      {:error, error} -> {:error, error}
    end
  end

  def check(_account), do: {:error, {:unauthorized, "vonage_credentials_missing"}}

  @impl true
  def parse_webhook(account, %{params: params}) do
    case account[:webhook_secret] do
      secret when is_binary(secret) and secret != "" ->
        if signed?(secret, params),
          do: {:ok, events(params)},
          else: {:error, :invalid_signature}

      _no_secret ->
        {:ok, events(params)}
    end
  end

  defp signed?(secret, %{"sig" => sig} = params) when is_binary(sig) do
    data = signed_data(params)
    sig = String.downcase(sig)

    Enum.any?(algorithms(byte_size(sig)), fn algorithm ->
      Http.secure_equal?(sig, digest(algorithm, secret, data))
    end)
  end

  defp signed?(_secret, _params), do: false

  @doc "Vonage's signed string: every parameter but `sig`, sorted, as `&name=value`."
  def signed_data(params) do
    params
    |> Map.delete("sig")
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map_join(fn {key, value} ->
      "&" <> key <> "=" <> String.replace(to_string(value), ["&", "="], "_")
    end)
  end

  @doc "The hex signature Vonage sends for `data` with `algorithm`."
  def digest(:md5hash, secret, data),
    do: :md5 |> :crypto.hash(data <> secret) |> Base.encode16(case: :lower)

  def digest(algorithm, secret, data),
    do: :hmac |> :crypto.mac(algorithm, secret, data) |> Base.encode16(case: :lower)

  defp algorithms(32), do: [:md5hash, :md5]
  defp algorithms(40), do: [:sha]
  defp algorithms(64), do: [:sha256]
  defp algorithms(128), do: [:sha512]
  defp algorithms(_length), do: []

  defp events(%{"messageId" => id, "status" => status} = params) when is_binary(id) do
    [
      %{
        type: :status,
        provider_message_id: id,
        status: status(status),
        provider_status: status,
        error_code: error_code(params["err-code"]),
        cost_cents: nil,
        currency: nil,
        occurred_at: nil,
        event_key: "vonage:#{id}:#{status}"
      }
    ]
  end

  defp events(%{"msisdn" => from, "text" => text}) when is_binary(from) and is_binary(text),
    do: [%{type: :inbound, channel: "sms", from: "+" <> String.trim_leading(from, "+"), text: text}]

  defp events(_params), do: []

  defp status("delivered"), do: "delivered"
  defp status(status) when status in ~w(expired failed rejected), do: "failed"
  defp status(_status), do: "sent"

  defp error_code(code) when code in [nil, "", "0", 0], do: nil
  defp error_code(code), do: to_string(code)

  defp base_url,
    do: Keyword.get(Application.get_env(:palee, __MODULE__, []), :base_url) || @default_base_url
end

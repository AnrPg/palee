defmodule Palee.Infrastructure.Channels.YubotoChannel do
  @moduledoc """
  Yuboto OMNI API (Octapush), a box's own account (ADR-396). SMS only.

    * auth: `Authorization: Basic <key>`, the OMNI API key Base64-encoded.
      Octapush shows it already encoded (My Account › API Integration); a
      key that is not valid Base64 is encoded here;
    * send: `POST https://services.yuboto.com/omni/v1/Send` with
      `contacts[].phonenumber` (digits), `dlr: true`, `callbackUrl` (the
      box's webhook URL; at most 255 characters, no `?`), `option1` (the
      message id) and `sms` (`sender`: a name of up to 11 characters or a
      number, `text`, `typesms` `unicode` for Greek else `sms`, `longsms`
      true, `validity` 1440 minutes); answers `ErrorCode` (0 is success)
      and `Message[].id`;
    * check: `POST /omni/v1/UserBalance` (`currentBalance`, `type`);
    * webhook: Yuboto calls the callback URL with a GET whose query holds
      `smsid`, `status` (1 delivered; 2 and 16 undelivered; -1, -2, -3
      rejected; -5 failed; -6 and -30 expired), `statusDescription`,
      `receiver`, `dlrDate`, `option1`. Yuboto does not sign it: the box's
      URL carries a secret token, checked before this adapter runs, and a
      receipt must name a message of this box.

  Errors (`ErrorCode`): 2, 23, 24, 25, 43, 44 and 45 are refused
  credentials or account; 4 (no credits) waits like Brevo's; 22 and 26
  (address blocked) are retried later; everything else refuses that
  message (`yuboto_<code>`; 108–111 are the sender name). Yuboto bills its
  own credits, so the outbox keeps its own estimate.

  https://octapush.yuboto.com/Data/pushc8b5-35c9-4b8c-9670-8f0dcb2ad364/OMNI_API_Documentation.pdf
  (OMNI API v1.10: §3.2 Authentication, §1 Send, §1.4 System Forwarded
  Callbacks, §1.4.5 status values, §5 User Balance, §16 Error Codes)
  """

  @behaviour Palee.Channels.Ports.MessagingChannel

  alias Palee.Channels.Domain.MessageText
  alias Palee.Infrastructure.Channels.Http

  @default_base_url "https://services.yuboto.com"
  @credential_codes [2, 23, 24, 25, 43, 44, 45]
  @transient_codes [4, 22, 26]

  @impl true
  def channels, do: ["sms"]

  @impl true
  def send_message(%{secret: key} = account, %{channel: "sms"} = outgoing) when is_binary(key) do
    case account[:sms_sender] do
      sender when is_binary(sender) and sender != "" ->
        payload =
          %{
            contacts: [%{phonenumber: String.trim_leading(outgoing.to, "+")}],
            sms: %{
              sender: String.trim_leading(sender, "+"),
              text: outgoing.body,
              typesms:
                if(MessageText.encoding(outgoing.body) == :ucs2, do: "unicode", else: "sms"),
              longsms: true,
              validity: 1440
            }
          }
          |> callback(outgoing)

        [method: :post, url: base_url() <> "/omni/v1/Send", headers: headers(key), json: payload]
        |> Http.request()
        |> accepted()

      _missing ->
        {:error, {:rejected, "sms_sender_missing"}}
    end
  end

  def send_message(%{secret: key}, %{channel: channel}) when is_binary(key),
    do: {:error, {:rejected, "channel_not_supported:" <> channel}}

  def send_message(_account, _outgoing), do: {:error, {:unauthorized, "yuboto_api_key_missing"}}

  defp callback(payload, %{callback_url: url, id: id}) when is_binary(url),
    do: Map.merge(payload, %{dlr: true, callbackUrl: url, option1: id})

  defp callback(payload, _outgoing), do: payload

  defp accepted({:ok, %{body: %{"ErrorCode" => 0, "Message" => [first | _rest]}}}) do
    case first do
      %{"id" => id, "errorCode" => code} when is_binary(id) and code in [0, nil] ->
        {:ok, %{provider_message_id: id, cost_cents: nil, currency: nil}}

      %{"errorCode" => code} when is_integer(code) ->
        {:error, code_error(code)}

      _other ->
        {:error, {:uncertain, "yuboto_unexpected_answer"}}
    end
  end

  defp accepted({:ok, %{body: %{"ErrorCode" => code}}}) when is_integer(code),
    do: {:error, code_error(code)}

  defp accepted({:ok, _unexpected}), do: {:error, {:uncertain, "yuboto_unexpected_answer"}}
  defp accepted({:error, error}), do: {:error, http_error(error)}

  @doc false
  def code_error(code) when code in @credential_codes, do: {:unauthorized, "yuboto_#{code}"}
  def code_error(code) when code in @transient_codes, do: {:transient, "yuboto_#{code}"}
  def code_error(code), do: {:rejected, "yuboto_#{code}"}

  defp http_error({kind, {:http, status}}), do: {kind, "yuboto_http_#{status}"}
  defp http_error({:rejected, {:http, status, _detail}}), do: {:rejected, "yuboto_http_#{status}"}
  defp http_error(other), do: other

  @impl true
  def check(%{secret: key}) when is_binary(key) do
    case Http.request(
           method: :post,
           url: base_url() <> "/omni/v1/UserBalance",
           headers: headers(key)
         ) do
      {:ok, %{body: %{"ErrorCode" => 0} = body}} ->
        {:ok, %{balance: body["currentBalance"], balance_type: body["type"]}}

      {:ok, %{body: %{"ErrorCode" => code}}} when is_integer(code) ->
        {:error, code_error(code)}

      {:ok, _unexpected} ->
        {:error, {:transient, "yuboto_unexpected_answer"}}

      {:error, error} ->
        {:error, http_error(error)}
    end
  end

  def check(_account), do: {:error, {:unauthorized, "yuboto_api_key_missing"}}

  @impl true
  def parse_webhook(_account, %{params: %{"smsid" => id, "status" => status} = params})
      when is_binary(id) and id != "" do
    code = integer(status)

    {:ok,
     [
       %{
         type: :status,
         provider_message_id: id,
         status: status(code),
         provider_status: params["statusDescription"] || to_string(status),
         error_code: if(status(code) == "failed", do: "yuboto_status_#{status}"),
         cost_cents: nil,
         currency: nil,
         occurred_at: nil,
         event_key: "yuboto:#{id}:#{status}"
       }
     ]}
  end

  def parse_webhook(_account, _request), do: {:ok, []}

  defp status(1), do: "delivered"
  defp status(code) when code in [2, 16, -1, -2, -3, -5, -6, -30], do: "failed"
  defp status(_code), do: "sent"

  defp integer(value) when is_integer(value), do: value

  defp integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} -> number
      _other -> nil
    end
  end

  defp integer(_value), do: nil

  @doc "The `Authorization` value of an OMNI API key (encoded once)."
  def authorization(key) do
    key = String.trim(key)

    case Base.decode64(key) do
      {:ok, _decoded} -> "Basic " <> key
      :error -> "Basic " <> Base.encode64(key)
    end
  end

  defp headers(key), do: [{"authorization", authorization(key)}, {"accept", "application/json"}]

  defp base_url,
    do: Keyword.get(Application.get_env(:palee, __MODULE__, []), :base_url) || @default_base_url
end

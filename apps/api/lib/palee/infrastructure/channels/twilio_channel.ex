defmodule Palee.Infrastructure.Channels.TwilioChannel do
  @moduledoc """
  Twilio Programmable Messaging, a box's own account (ADR-396). SMS only.

    * send: `POST /2010-04-01/Accounts/{AccountSid}/Messages.json`, HTTP
      basic auth (Account SID, Auth Token), form fields `To`, `From` (a
      name of up to 11 characters, a number) or `MessagingServiceSid`
      (`MG…`), `Body` and `StatusCallback` (the box's webhook URL);
      answers the message `sid`;
    * check: `GET /2010-04-01/Accounts/{AccountSid}.json`;
    * webhook: status callbacks (`MessageSid`, `MessageStatus`,
      `ErrorCode`) and inbound texts (`From`, `Body`), form-encoded and
      signed with `X-Twilio-Signature` = Base64(HMAC-SHA1(Auth Token, URL
      followed by every POST parameter's name and value, sorted by name)).
      An unsigned or wrongly signed call is refused.

  Errors: 401/403 and Twilio code 20003 are refused credentials; 429 and
  5xx are retried; code 21610 (the person replied STOP to Twilio) and other
  4xx codes refuse that message (`twilio_<code>`). Twilio prices a message
  only later and in USD, so the outbox keeps its own estimate.

  https://www.twilio.com/docs/messaging/api/message-resource#create-a-message-resource
  https://www.twilio.com/docs/messaging/guides/track-outbound-message-status
  https://www.twilio.com/docs/usage/webhooks/webhooks-security
  https://www.twilio.com/docs/api/errors
  """

  @behaviour Palee.Channels.Ports.MessagingChannel

  alias Palee.Infrastructure.Channels.Http

  @default_base_url "https://api.twilio.com"

  @impl true
  def channels, do: ["sms"]

  @impl true
  def send_message(%{account_id: sid, secret: token} = account, %{channel: "sms"} = outgoing)
      when is_binary(sid) and is_binary(token) do
    case account[:sms_sender] do
      sender when is_binary(sender) and sender != "" ->
        form =
          [{"To", outgoing.to}, sender_field(sender), {"Body", outgoing.body}] ++
            callback(outgoing)

        [
          method: :post,
          url: base_url() <> "/2010-04-01/Accounts/#{sid}/Messages.json",
          auth: {:basic, "#{sid}:#{token}"},
          form: form
        ]
        |> Http.request()
        |> accepted()

      _missing ->
        {:error, {:rejected, "sms_sender_missing"}}
    end
  end

  def send_message(%{account_id: sid, secret: token}, %{channel: channel})
      when is_binary(sid) and is_binary(token),
      do: {:error, {:rejected, "channel_not_supported:" <> channel}}

  def send_message(_account, _outgoing),
    do: {:error, {:unauthorized, "twilio_credentials_missing"}}

  defp accepted({:ok, %{body: %{"sid" => message_sid}}}) when is_binary(message_sid),
    do: {:ok, %{provider_message_id: message_sid, cost_cents: nil, currency: nil}}

  defp accepted({:ok, _unexpected}), do: {:error, {:uncertain, "twilio_unexpected_answer"}}
  defp accepted({:error, error}), do: {:error, error(error)}

  @doc false
  def error({:rejected, {:http, _status, detail}}) do
    case code(detail) do
      "20003" -> {:unauthorized, "twilio_20003"}
      nil -> {:rejected, "twilio_rejected"}
      code -> {:rejected, "twilio_" <> code}
    end
  end

  def error({kind, {:http, status}}), do: {kind, "twilio_http_#{status}"}
  def error(other), do: other

  # Http keeps the answer's `code` and `message` as an inspected map.
  defp code(detail) when is_binary(detail) do
    case Regex.run(~r/"code" => (\d+)/, detail) do
      [_match, code] -> code
      nil -> nil
    end
  end

  defp code(_detail), do: nil

  # A Messaging Service (MG…) picks the sender itself.
  defp sender_field("MG" <> rest = service) when byte_size(rest) == 32,
    do: {"MessagingServiceSid", service}

  defp sender_field(sender), do: {"From", sender}

  defp callback(%{callback_url: url}) when is_binary(url), do: [{"StatusCallback", url}]
  defp callback(_outgoing), do: []

  @impl true
  def check(%{account_id: sid, secret: token}) when is_binary(sid) and is_binary(token) do
    case Http.request(
           method: :get,
           url: base_url() <> "/2010-04-01/Accounts/#{sid}.json",
           auth: {:basic, "#{sid}:#{token}"}
         ) do
      {:ok, %{body: body}} -> {:ok, %{account_status: is_map(body) && body["status"]}}
      {:error, error} -> {:error, error(error)}
    end
  end

  def check(_account), do: {:error, {:unauthorized, "twilio_credentials_missing"}}

  @impl true
  def parse_webhook(%{secret: token}, %{url: url, params: params, headers: headers})
      when is_binary(token) and is_binary(url) do
    if Http.secure_equal?(Http.header(headers, "x-twilio-signature") || "", signature(token, url, params)),
      do: {:ok, events(params)},
      else: {:error, :invalid_signature}
  end

  def parse_webhook(_account, _request), do: {:error, :invalid_signature}

  @doc "Twilio's signature of a webhook posted to `url` with the form `params`."
  def signature(token, url, params) do
    data =
      params
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map_join(fn {key, value} -> key <> to_string(value) end)

    :hmac |> :crypto.mac(:sha, token, url <> data) |> Base.encode64()
  end

  defp events(%{"MessageSid" => sid, "MessageStatus" => status} = params) when is_binary(sid) do
    [
      %{
        type: :status,
        provider_message_id: sid,
        status: status(status),
        provider_status: status,
        error_code: params["ErrorCode"],
        cost_cents: nil,
        currency: nil,
        occurred_at: nil,
        event_key: "twilio:#{sid}:#{status}"
      }
    ]
  end

  defp events(%{"From" => from, "Body" => text}) when is_binary(from) and is_binary(text),
    do: [%{type: :inbound, channel: "sms", from: from, text: text}]

  defp events(_params), do: []

  defp status("delivered"), do: "delivered"
  defp status(status) when status in ~w(undelivered failed canceled), do: "failed"
  defp status(_status), do: "sent"

  defp base_url,
    do: Keyword.get(Application.get_env(:palee, __MODULE__, []), :base_url) || @default_base_url
end

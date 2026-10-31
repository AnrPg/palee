defmodule Palee.Infrastructure.Channels.TwilioChannel do
  @moduledoc """
  Twilio Programmable Messaging (ADR-348 §3): SMS (alphanumeric sender in
  Greece and Cyprus) and WhatsApp (Content API templates). No Viber.

    * send: `POST /2010-04-01/Accounts/{AccountSid}/Messages.json` with
      HTTP basic auth (Account SID, Auth Token), `To`, `From` (or a
      Messaging Service `MG…`), `Body` or `ContentSid` + `ContentVariables`,
      and `StatusCallback` (the box's webhook URL);
    * check: `GET /2010-04-01/Accounts/{AccountSid}.json`;
    * webhook: status callbacks and inbound texts, form-encoded, signed with
      `X-Twilio-Signature` = Base64(HMAC-SHA1(AuthToken, URL + every POST
      parameter name and value, sorted by name)).

  https://www.twilio.com/docs/messaging/api/message-resource
  https://www.twilio.com/docs/usage/webhooks/webhooks-security
  """

  @behaviour Palee.Channels.Ports.MessagingChannel

  alias Palee.Infrastructure.Channels.Http

  @default_base_url "https://api.twilio.com"

  @impl true
  def channels, do: ~w(sms whatsapp)

  @impl true
  def send_message(%{account_id: sid, secret: token} = account, outgoing)
      when is_binary(sid) and is_binary(token) do
    with {:ok, form} <- form(account, outgoing),
         {:ok, %{body: body}} <-
           Http.request(
             method: :post,
             url: base_url(account) <> "/2010-04-01/Accounts/#{sid}/Messages.json",
             auth: {:basic, "#{sid}:#{token}"},
             form: form
           ) do
      case body do
        %{"sid" => message_sid} ->
          {:ok,
           %{
             provider_message_id: message_sid,
             cost_cents: Http.cents(body["price"]),
             currency: body["price_unit"]
           }}

        _other ->
          {:error, {:uncertain, "twilio_unexpected_answer"}}
      end
    end
  end

  def send_message(_account, _outgoing), do: {:error, {:unauthorized, "twilio_credentials_missing"}}

  defp form(account, %{channel: "sms"} = outgoing) do
    case account[:sms_sender] do
      sender when is_binary(sender) and sender != "" ->
        {:ok, [{"To", outgoing.to}, sender_field(sender), {"Body", outgoing.body}] ++ callback(outgoing)}

      _missing ->
        {:error, {:rejected, "sms_sender_missing"}}
    end
  end

  defp form(account, %{channel: "whatsapp", template: %{} = template} = outgoing) do
    case account[:whatsapp_sender] do
      sender when is_binary(sender) and sender != "" ->
        variables =
          template.values
          |> Enum.with_index(1)
          |> Map.new(fn {value, index} -> {Integer.to_string(index), value} end)

        {:ok,
         [
           {"To", "whatsapp:" <> outgoing.to},
           whatsapp_sender(sender),
           {"ContentSid", template.provider_template_id},
           {"ContentVariables", Jason.encode!(variables)}
         ] ++ callback(outgoing)}

      _missing ->
        {:error, {:rejected, "whatsapp_sender_missing"}}
    end
  end

  defp form(_account, %{channel: "whatsapp"}), do: {:error, {:rejected, "whatsapp_template_missing"}}
  defp form(_account, %{channel: channel}), do: {:error, {:rejected, "channel_not_supported:" <> channel}}

  # A Messaging Service (MG…) picks the sender itself.
  defp sender_field("MG" <> _rest = service), do: {"MessagingServiceSid", service}
  defp sender_field(sender), do: {"From", sender}

  defp whatsapp_sender("MG" <> _rest = service), do: {"MessagingServiceSid", service}
  defp whatsapp_sender("whatsapp:" <> _rest = sender), do: {"From", sender}
  defp whatsapp_sender(sender), do: {"From", "whatsapp:" <> sender}

  defp callback(%{callback_url: url}) when is_binary(url), do: [{"StatusCallback", url}]
  defp callback(_outgoing), do: []

  @impl true
  def check(%{account_id: sid, secret: token} = account) when is_binary(sid) and is_binary(token) do
    with {:ok, %{body: body}} <-
           Http.request(
             method: :get,
             url: base_url(account) <> "/2010-04-01/Accounts/#{sid}.json",
             auth: {:basic, "#{sid}:#{token}"}
           ) do
      {:ok, %{account_status: is_map(body) && body["status"]}}
    end
  end

  def check(_account), do: {:error, {:unauthorized, "twilio_credentials_missing"}}

  @impl true
  def parse_webhook(%{secret: token}, %{url: url, params: params, headers: headers})
      when is_binary(token) do
    expected = signature(token, url, params)

    if Http.secure_equal?(Http.header(headers, "x-twilio-signature") || "", expected),
      do: {:ok, events(params)},
      else: {:error, :invalid_signature}
  end

  def parse_webhook(_account, _request), do: {:error, :invalid_signature}

  @doc "Twilio's request signature of `url` and the POST `params`."
  def signature(token, url, params) do
    data =
      params
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map_join(fn {key, value} -> key <> to_string(value) end)

    :hmac |> :crypto.mac(:sha, token, url <> data) |> Base.encode64()
  end

  defp events(%{"MessageSid" => sid, "MessageStatus" => status} = params) do
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

  defp events(%{"From" => from, "Body" => text}) do
    case from do
      "whatsapp:" <> number -> [%{type: :inbound, channel: "whatsapp", from: number, text: text}]
      number -> [%{type: :inbound, channel: "sms", from: number, text: text}]
    end
  end

  defp events(_params), do: []

  defp status(status) when status in ~w(delivered read), do: "delivered"
  defp status(status) when status in ~w(undelivered failed canceled), do: "failed"
  defp status(_status), do: "sent"

  defp base_url(_account),
    do: Keyword.get(Application.get_env(:palee, __MODULE__, []), :base_url) || @default_base_url
end

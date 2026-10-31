defmodule Palee.Infrastructure.Channels.InfobipChannel do
  @moduledoc """
  Infobip (ADR-348 §3): SMS, Viber Business Messages (Infobip is an
  official Viber partner) and WhatsApp templates, one account and one
  balance. Each account has its own base URL (`https://xxxxx.api.infobip.com`)
  and an API key sent as `Authorization: App <key>`.

    * SMS: `POST /sms/2/text/advanced`;
    * Viber: `POST /viber/2/messages` (text, billed as transactional);
    * WhatsApp: `POST /whatsapp/1/message/template`;
    * check: `GET /account/1/balance`;
    * webhook: delivery reports and inbound texts as JSON `{"results": [...]}`.
      Infobip does not sign them: the box's webhook URL carries a secret
      token (checked before this adapter runs), and the report must name a
      message of this box.

  https://www.infobip.com/docs/api/channels/sms/sms-messaging/outbound-sms/send-sms-message
  https://www.infobip.com/docs/api/channels/viber/viber-business-messages/send-viber-messages
  https://www.infobip.com/docs/api/channels/whatsapp/whatsapp-outbound-messages/send-whatsapp-template-message
  """

  @behaviour Palee.Channels.Ports.MessagingChannel

  alias Palee.Infrastructure.Channels.Http

  @impl true
  def channels, do: ~w(sms viber whatsapp)

  @impl true
  def send_message(%{secret: key, base_url: base} = account, outgoing)
      when is_binary(key) and is_binary(base) do
    with {:ok, path, payload} <- payload(account, outgoing),
         {:ok, %{body: body}} <-
           Http.request(
             method: :post,
             url: String.trim_trailing(base, "/") <> path,
             headers: [{"authorization", "App " <> key}, {"accept", "application/json"}],
             json: payload
           ) do
      accepted(body, outgoing)
    end
  end

  def send_message(_account, _outgoing), do: {:error, {:unauthorized, "infobip_credentials_missing"}}

  defp payload(account, %{channel: "sms"} = outgoing) do
    with {:ok, sender} <- sender(account, :sms_sender) do
      {:ok, "/sms/2/text/advanced",
       %{
         messages: [
           %{
             destinations: [%{to: digits(outgoing.to), messageId: outgoing.id}],
             from: sender,
             text: outgoing.body,
             callbackData: outgoing.id
           }
           |> notify(outgoing, :notifyUrl)
         ]
       }}
    end
  end

  defp payload(account, %{channel: "viber"} = outgoing) do
    with {:ok, sender} <- sender(account, :viber_sender) do
      message =
        %{
          sender: sender,
          destinations: [%{to: digits(outgoing.to), messageId: outgoing.id}],
          content: %{text: outgoing.body, type: "TEXT"},
          callbackData: outgoing.id
        }

      message =
        case outgoing.callback_url do
          url when is_binary(url) -> Map.put(message, :webhooks, %{delivery: %{url: url}})
          _none -> message
        end

      {:ok, "/viber/2/messages", %{messages: [message]}}
    end
  end

  defp payload(account, %{channel: "whatsapp", template: %{} = template} = outgoing) do
    with {:ok, sender} <- sender(account, :whatsapp_sender) do
      {:ok, "/whatsapp/1/message/template",
       %{
         messages: [
           %{
             from: digits(sender),
             to: digits(outgoing.to),
             messageId: outgoing.id,
             content: %{
               templateName: template.provider_template_id,
               templateData: %{body: %{placeholders: template.values}},
               language: whatsapp_language(template.locale)
             },
             callbackData: outgoing.id
           }
           |> notify(outgoing, :notifyUrl)
         ]
       }}
    end
  end

  defp payload(_account, %{channel: "whatsapp"}), do: {:error, {:rejected, "whatsapp_template_missing"}}
  defp payload(_account, %{channel: channel}), do: {:error, {:rejected, "channel_not_supported:" <> channel}}

  defp sender(account, field) do
    case account[field] do
      sender when is_binary(sender) and sender != "" -> {:ok, sender}
      _missing -> {:error, {:rejected, "#{field}_missing"}}
    end
  end

  defp notify(message, %{callback_url: url}, key) when is_binary(url),
    do: Map.merge(message, %{key => url, notifyContentType: "application/json"})

  defp notify(message, _outgoing, _key), do: message

  defp digits(number), do: String.replace(number, ~r/[^0-9]/, "")

  # Meta's language codes: el, en, en_GB, pt_PT…
  defp whatsapp_language(locale), do: String.replace(locale || "en", "-", "_")

  defp accepted(%{"messages" => [first | _rest]}, outgoing) do
    case get_in(first, ["status", "groupName"]) do
      "REJECTED" ->
        {:error, {:rejected, get_in(first, ["status", "name"]) || "rejected"}}

      _accepted ->
        {:ok,
         %{
           provider_message_id: first["messageId"] || outgoing.id,
           cost_cents: nil,
           currency: nil
         }}
    end
  end

  defp accepted(_body, _outgoing), do: {:error, {:uncertain, "infobip_unexpected_answer"}}

  @impl true
  def check(%{secret: key, base_url: base}) when is_binary(key) and is_binary(base) do
    with {:ok, %{body: body}} <-
           Http.request(
             method: :get,
             url: String.trim_trailing(base, "/") <> "/account/1/balance",
             headers: [{"authorization", "App " <> key}, {"accept", "application/json"}]
           ) do
      {:ok,
       %{
         balance_cents: is_map(body) && Http.cents(body["balance"]),
         currency: is_map(body) && body["currency"]
       }}
    end
  end

  def check(_account), do: {:error, {:unauthorized, "infobip_credentials_missing"}}

  @impl true
  def parse_webhook(_account, %{params: %{"results" => results}}) when is_list(results),
    do: {:ok, Enum.flat_map(results, &event/1)}

  def parse_webhook(_account, _request), do: {:ok, []}

  defp event(%{"messageId" => id, "status" => %{"groupName" => group} = status} = result) do
    [
      %{
        type: :status,
        provider_message_id: id,
        status: status(group),
        provider_status: status["name"] || group,
        error_code: get_in(result, ["error", "name"]) |> ok_error(),
        cost_cents: Http.cents(get_in(result, ["price", "pricePerMessage"])),
        currency: get_in(result, ["price", "currency"]),
        occurred_at: timestamp(result["doneAt"]),
        event_key: "infobip:#{id}:#{group}"
      }
    ]
  end

  defp event(%{"from" => from} = result) do
    text = result["cleanText"] || result["text"] || get_in(result, ["message", "text"])
    channel = if result["integrationType"] == "WHATSAPP", do: "whatsapp", else: inbound_channel(result)
    [%{type: :inbound, channel: channel, from: "+" <> digits(from), text: text}]
  end

  defp event(_result), do: []

  defp inbound_channel(%{"channel" => "VIBER"}), do: "viber"
  defp inbound_channel(%{"message" => %{}}), do: "viber"
  defp inbound_channel(_result), do: "sms"

  defp ok_error("NO_ERROR"), do: nil
  defp ok_error(other), do: other

  defp status("DELIVERED"), do: "delivered"
  defp status(group) when group in ~w(UNDELIVERABLE EXPIRED REJECTED), do: "failed"
  defp status(_group), do: "sent"

  defp timestamp(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, at, _offset} -> at
      _invalid -> nil
    end
  end

  defp timestamp(_value), do: nil
end

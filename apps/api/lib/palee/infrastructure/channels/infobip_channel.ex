defmodule Palee.Infrastructure.Channels.InfobipChannel do
  @moduledoc """
  Infobip SMS API v3, a box's own account (ADR-396). SMS only. Each
  account has its own base URL (`https://<id>.api.infobip.com`, checked by
  `Channels.Domain.VendorRules.infobip_base_url?/1`) and an API key sent as
  `Authorization: App <key>`.

    * send: `POST /sms/3/messages` with `messages[].sender`,
      `destinations[].to` (digits) and `messageId` (the message id),
      `content.text`, `webhooks.delivery.url` (the box's webhook URL),
      `webhooks.contentType` and `webhooks.callbackData`; answers the
      message's `status.groupName` (`PENDING`, or `REJECTED` with a name);
    * check: `GET /account/1/balance` (balance and currency);
    * webhook: delivery reports `{"results": [...]}` with `messageId`,
      `status.groupName` (`DELIVERED`, `UNDELIVERABLE`, `EXPIRED`,
      `REJECTED`, `PENDING`), `error.name` and `price`; inbound texts
      (`from`, `text`) when the box points its number's forwarding here.
      Infobip does not sign per-message reports: the box's URL carries a
      secret token, checked before this adapter runs, and a report must
      name a message of this box.

  Errors: 401/403 refused credentials, 429/5xx retried, other 4xx and a
  `REJECTED` status refuse that message (`infobip_<status name>`). A price
  in EUR in the report becomes the message's cost; other currencies keep
  the outbox's estimate.

  https://www.infobip.com/docs/api/channels/sms (OpenAPI: https://api.infobip.com/platform/1/openapi/sms)
  https://www.infobip.com/docs/essentials/api-essentials/response-status-and-error-codes
  https://www.infobip.com/docs/api/platform/account-management/get-account-balance
  https://www.infobip.com/docs/essentials/api-essentials/api-authentication
  """

  @behaviour Palee.Channels.Ports.MessagingChannel

  alias Palee.Channels.Domain.VendorRules
  alias Palee.Infrastructure.Channels.Http

  @impl true
  def channels, do: ["sms"]

  @impl true
  def send_message(%{secret: key, base_url: base} = account, %{channel: "sms"} = outgoing)
      when is_binary(key) and is_binary(base) do
    with {:ok, base} <- base(base),
         {:ok, sender} <- sender(account) do
      message =
        %{
          sender: sender,
          destinations: [%{to: digits(outgoing.to), messageId: outgoing.id}],
          content: %{text: outgoing.body}
        }
        |> webhooks(outgoing)

      [
        method: :post,
        url: base <> "/sms/3/messages",
        headers: headers(key),
        json: %{messages: [message]}
      ]
      |> Http.request()
      |> accepted(outgoing)
    end
  end

  def send_message(%{secret: key, base_url: base}, %{channel: channel})
      when is_binary(key) and is_binary(base),
      do: {:error, {:rejected, "channel_not_supported:" <> channel}}

  def send_message(_account, _outgoing),
    do: {:error, {:unauthorized, "infobip_credentials_missing"}}

  defp base(base) do
    if VendorRules.infobip_base_url?(base),
      do: {:ok, String.trim_trailing(base, "/")},
      else: {:error, {:unauthorized, "infobip_base_url_invalid"}}
  end

  defp sender(account) do
    case account[:sms_sender] do
      sender when is_binary(sender) and sender != "" -> {:ok, String.trim_leading(sender, "+")}
      _missing -> {:error, {:rejected, "sms_sender_missing"}}
    end
  end

  defp webhooks(message, %{callback_url: url, id: id}) when is_binary(url),
    do:
      Map.put(message, :webhooks, %{
        delivery: %{url: url},
        contentType: "application/json",
        callbackData: id
      })

  defp webhooks(message, _outgoing), do: message

  defp accepted({:ok, %{body: %{"messages" => [first | _rest]}}}, outgoing) do
    case first["status"] do
      %{"groupName" => "REJECTED"} = status ->
        {:error, {:rejected, "infobip_" <> (status["name"] || "REJECTED")}}

      _accepted ->
        {:ok,
         %{provider_message_id: first["messageId"] || outgoing.id, cost_cents: nil, currency: nil}}
    end
  end

  defp accepted({:ok, _unexpected}, _outgoing),
    do: {:error, {:uncertain, "infobip_unexpected_answer"}}

  defp accepted({:error, error}, _outgoing), do: {:error, error(error)}

  defp error({kind, {:http, status}}), do: {kind, "infobip_http_#{status}"}
  defp error({:rejected, {:http, status, _detail}}), do: {:rejected, "infobip_http_#{status}"}
  defp error(other), do: other

  @impl true
  def check(%{secret: key, base_url: base}) when is_binary(key) and is_binary(base) do
    with {:ok, base} <- base(base) do
      case Http.request(method: :get, url: base <> "/account/1/balance", headers: headers(key)) do
        {:ok, %{body: %{} = body}} ->
          {:ok, %{balance: body["balance"], currency: body["currency"]}}

        {:ok, _other} ->
          {:ok, %{balance: nil, currency: nil}}

        {:error, error} ->
          {:error, error(error)}
      end
    end
  end

  def check(_account), do: {:error, {:unauthorized, "infobip_credentials_missing"}}

  @impl true
  def parse_webhook(_account, %{params: %{"results" => results}}) when is_list(results),
    do: {:ok, Enum.flat_map(results, &event/1)}

  def parse_webhook(_account, _request), do: {:ok, []}

  defp event(%{"messageId" => id, "status" => %{"groupName" => group} = status} = result)
       when is_binary(id) do
    {cents, currency} = price(result["price"])

    [
      %{
        type: :status,
        provider_message_id: id,
        status: status(group),
        provider_status: status["name"] || group,
        error_code: error_name(result["error"]),
        cost_cents: cents,
        currency: currency,
        occurred_at: timestamp(result["doneAt"]),
        event_key: "infobip:#{id}:#{group}"
      }
    ]
  end

  defp event(%{"from" => from} = result) when is_binary(from) do
    case result["cleanText"] || result["text"] do
      text when is_binary(text) ->
        [%{type: :inbound, channel: "sms", from: "+" <> digits(from), text: text}]

      _none ->
        []
    end
  end

  defp event(_result), do: []

  defp price(%{"pricePerMessage" => amount, "currency" => "EUR"})
       when is_number(amount) and amount > 0,
       do: {Http.cents(amount), "EUR"}

  defp price(_price), do: {nil, nil}

  defp error_name(%{"name" => "NO_ERROR"}), do: nil
  defp error_name(%{"name" => name}) when is_binary(name), do: name
  defp error_name(_error), do: nil

  defp status("DELIVERED"), do: "delivered"
  defp status(group) when group in ~w(UNDELIVERABLE EXPIRED REJECTED), do: "failed"
  defp status(_group), do: "sent"

  defp timestamp(value) when is_binary(value) do
    # Infobip writes `2026-11-03T10:15:00.000+0000`; ISO 8601 wants a colon.
    value = Regex.replace(~r/([+-]\d{2})(\d{2})$/, value, "\\1:\\2")

    case DateTime.from_iso8601(value) do
      {:ok, at, _offset} -> %{at | microsecond: {elem(at.microsecond, 0), 6}}
      _invalid -> nil
    end
  end

  defp timestamp(_value), do: nil

  defp digits(number), do: String.replace(number, ~r/[^0-9]/, "")

  defp headers(key), do: [{"authorization", "App " <> key}, {"accept", "application/json"}]
end

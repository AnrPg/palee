defmodule Palee.Infrastructure.Channels.BrevoChannel do
  @moduledoc """
  Brevo transactional SMS (ADR-348 §3; the product owner's choice of
  2026-10-31: the same Brevo account Palee already uses for email). SMS
  only; Brevo bills prepaid SMS credits per country.

    * send: `POST /v3/transactionalSMS/sms` with the `api-key` header,
      `sender` (up to 11 letters/digits, or a number), `recipient` (digits
      with the country code), `content`, `type` (`transactional` for
      service messages, `marketing` for marketing ones), `tag`, `webUrl`
      (the box's webhook URL for this message's events) and
      `unicodeEnabled` for texts outside the GSM alphabet (Greek);
      answers `messageId`, `smsCount`, `usedCredits`, `remainingCredits`;
    * check: `GET /v3/account` (the SMS credits left);
    * webhook: JSON with `messageId`, `msg_status` (`sent`, `delivered`,
      `soft_bounce`, `hard_bounce`, `rej`, `bl`, `replied`,
      `unsubscribed`), `to`, `reply`, `credits_used`. Brevo does not sign
      it: the box's URL carries a secret token, checked before this
      adapter runs, and a receipt must name a message of this box.

  Credits become cents with `config :palee, #{inspect(__MODULE__)},
  credit_cents: …` (the price Palee pays per credit); without it the
  outbox keeps its own estimate.

  https://developers.brevo.com/reference/sendtransacsms
  https://developers.brevo.com/docs/transactional-webhooks
  """

  @behaviour Palee.Channels.Ports.MessagingChannel

  alias Palee.Channels.Domain.MessageText
  alias Palee.Infrastructure.Channels.Http

  @default_base_url "https://api.brevo.com"
  @tag "palee-channels"

  @impl true
  def channels, do: ["sms"]

  @impl true
  def send_message(%{secret: key} = account, %{channel: "sms"} = outgoing) when is_binary(key) do
    case account[:sms_sender] do
      sender when is_binary(sender) and sender != "" -> post(key, sender, outgoing)
      _missing -> {:error, {:rejected, "sms_sender_missing"}}
    end
  end

  def send_message(%{secret: key}, %{channel: channel}) when is_binary(key),
    do: {:error, {:rejected, "channel_not_supported:" <> channel}}

  def send_message(_account, _outgoing), do: {:error, {:unauthorized, "brevo_api_key_missing"}}

  defp post(key, sender, outgoing) do
    payload =
      %{
        sender: sender,
        recipient: String.trim_leading(outgoing.to, "+"),
        content: outgoing.body,
        type: if(outgoing.purpose == "marketing", do: "marketing", else: "transactional"),
        tag: @tag,
        unicodeEnabled: MessageText.encoding(outgoing.body) == :ucs2
      }
      |> then(fn payload ->
        case outgoing.callback_url do
          url when is_binary(url) -> Map.put(payload, :webUrl, url)
          _none -> payload
        end
      end)

    case Http.request(
           method: :post,
           url: base_url() <> "/v3/transactionalSMS/sms",
           headers: headers(key),
           json: payload
         ) do
      {:ok, %{body: %{"messageId" => id} = body}} ->
        {:ok,
         %{
           provider_message_id: to_string(id),
           cost_cents: credits_to_cents(body["usedCredits"]),
           currency: if(credit_cents(), do: "EUR")
         }}

      {:ok, _unexpected} ->
        {:error, {:uncertain, "brevo_unexpected_answer"}}

      # Out of SMS credits: nothing was sent; it goes once credits are topped up.
      {:error, {:rejected, {:http, 402, _detail}}} ->
        {:error, {:transient, "brevo_not_enough_credits"}}

      {:error, {:rejected, {:http, 400, detail}}} = error ->
        if is_binary(detail) and String.contains?(detail, "not_enough_credits"),
          do: {:error, {:transient, "brevo_not_enough_credits"}},
          else: error

      error ->
        error
    end
  end

  @impl true
  def check(%{secret: key}) when is_binary(key) do
    with {:ok, %{body: body}} <-
           Http.request(method: :get, url: base_url() <> "/v3/account", headers: headers(key)) do
      credits =
        body
        |> then(&((is_map(&1) && &1["plan"]) || []))
        |> Enum.find_value(fn plan -> plan["type"] == "sms" && plan["credits"] end)

      {:ok, %{sms_credits: credits}}
    end
  end

  def check(_account), do: {:error, {:unauthorized, "brevo_api_key_missing"}}

  @impl true
  def parse_webhook(_account, %{params: params}) do
    case params do
      %{"messageId" => id, "msg_status" => status} when not is_nil(id) ->
        {:ok, events(to_string(id), status, params)}

      _other ->
        {:ok, []}
    end
  end

  defp events(_id, "replied", params),
    do: [%{type: :inbound, channel: "sms", from: phone(params["to"]), text: params["reply"]}]

  # Brevo's own unsubscribe (a STOP it handled itself) stops the number here too.
  defp events(_id, "unsubscribed", params),
    do: [%{type: :inbound, channel: "sms", from: phone(params["to"]), text: "STOP"}]

  defp events(id, status, params) do
    [
      %{
        type: :status,
        provider_message_id: id,
        status: status(status),
        provider_status: status,
        error_code: error_code(status, params),
        cost_cents: credits_to_cents(params["credits_used"]),
        currency: if(credit_cents() && params["credits_used"], do: "EUR"),
        occurred_at: occurred_at(params["ts_event"]),
        event_key: "brevo:#{id}:#{status}"
      }
    ]
  end

  defp status("delivered"), do: "delivered"
  defp status(status) when status in ~w(soft_bounce hard_bounce rej bl), do: "failed"
  defp status(_status), do: "sent"

  defp error_code(status, _params) when status in ~w(soft_bounce hard_bounce), do: status
  defp error_code("rej", _params), do: "rejected"
  defp error_code("bl", _params), do: "blacklisted"
  defp error_code(_status, _params), do: nil

  defp occurred_at(ts) when is_integer(ts) do
    case DateTime.from_unix(ts) do
      {:ok, at} -> %{at | microsecond: {0, 6}}
      _invalid -> nil
    end
  end

  defp occurred_at(_ts), do: nil

  defp phone(to) when is_binary(to), do: "+" <> String.trim_leading(to, "+")
  defp phone(_to), do: ""

  defp credits_to_cents(credits) when is_number(credits) do
    case credit_cents() do
      nil -> nil
      price -> ceil(credits * price)
    end
  end

  defp credits_to_cents(_credits), do: nil

  defp credit_cents, do: Keyword.get(Application.get_env(:palee, __MODULE__, []), :credit_cents)

  defp headers(key), do: [{"api-key", key}, {"accept", "application/json"}]

  defp base_url,
    do: Keyword.get(Application.get_env(:palee, __MODULE__, []), :base_url) || @default_base_url
end

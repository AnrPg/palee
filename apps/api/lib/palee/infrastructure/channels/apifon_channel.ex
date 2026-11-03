defmodule Palee.Infrastructure.Channels.ApifonChannel do
  @moduledoc """
  Apifon SMS Gateway REST API, a box's own account (ADR-396). SMS only.

    * auth: every request is signed. `Authorization: ApifonWS
      <token>:<signature>` and `X-ApifonWS-Date` (RFC 1123, GMT), where the
      signature is Base64(HMAC-SHA256(secret key, method + "\\n" + path +
      "\\n" + body + "\\n" + date)). The date must be within 15 minutes of
      Apifon's clock;
    * send: `POST https://ars.apifon.com/services/api/v1/sms/send` with
      `subscribers[].number` (digits) and `custom_id` (the message id),
      `message` (`text`, `sender_id`: a name of up to 11 characters or a
      number, `dc` 2 for UCS-2 when the text is Greek, else 0),
      `callback_url` (the box's webhook URL) and `reference_id`; answers
      `results` per number with the `message_id`, and `result_info`;
    * check: `POST /services/api/v1/balance` with an empty body;
    * webhook: JSON `{"data": [...]}` with `message_id`, `status.code`
      (7 delivered; 1, 5, 8, 18–24 and 101–115 failed; 3, 4 on the way) and
      `error_code`, and the reply callback (`from`, `text`) of two-way
      numbers. Apifon does not sign callbacks: the box's URL carries a
      secret token, checked before this adapter runs, and a receipt must
      name a message of this box.

  Errors: 401 (or `result_info.status_code` 401) refused credentials,
  429/5xx retried, 403 and other 4xx refuse that message (`apifon_<code>`).
  Apifon reports prices without a currency, so the outbox keeps its own
  estimate.

  https://docs.apifon.com/authentication.html
  https://docs.apifon.com/apireference.html (SMS Request, SMS Response, SMS
  Callback Statuses, Balance Request)
  """

  @behaviour Palee.Channels.Ports.MessagingChannel

  alias Palee.Channels.Domain.MessageText
  alias Palee.Infrastructure.Channels.Http

  @default_base_url "https://ars.apifon.com"
  @send_path "/services/api/v1/sms/send"
  @balance_path "/services/api/v1/balance"
  @failed_codes [1, 5, 8, 18, 19, 21, 22, 23, 24] ++ Enum.to_list(101..115)

  @impl true
  def channels, do: ["sms"]

  @impl true
  def send_message(%{account_id: token, secret: secret} = account, %{channel: "sms"} = outgoing)
      when is_binary(token) and is_binary(secret) do
    case account[:sms_sender] do
      sender when is_binary(sender) and sender != "" ->
        payload =
          %{
            subscribers: [%{number: String.trim_leading(outgoing.to, "+"), custom_id: outgoing.id}],
            reference_id: outgoing.id,
            message: %{
              text: outgoing.body,
              sender_id: String.trim_leading(sender, "+"),
              dc: if(MessageText.encoding(outgoing.body) == :ucs2, do: 2, else: 0)
            }
          }
          |> callback(outgoing)

        account
        |> signed_request(@send_path, Jason.encode!(payload))
        |> accepted(outgoing)

      _missing ->
        {:error, {:rejected, "sms_sender_missing"}}
    end
  end

  def send_message(%{account_id: token, secret: secret}, %{channel: channel})
      when is_binary(token) and is_binary(secret),
      do: {:error, {:rejected, "channel_not_supported:" <> channel}}

  def send_message(_account, _outgoing),
    do: {:error, {:unauthorized, "apifon_credentials_missing"}}

  defp callback(payload, %{callback_url: url}) when is_binary(url),
    do: Map.put(payload, :callback_url, url)

  defp callback(payload, _outgoing), do: payload

  defp signed_request(%{account_id: token, secret: secret}, path, body) do
    date = Calendar.strftime(DateTime.utc_now(), "%a, %d %b %Y %H:%M:%S GMT")

    Http.request(
      method: :post,
      url: base_url() <> path,
      headers: [
        {"authorization", "ApifonWS #{token}:#{signature(secret, "POST", path, body, date)}"},
        {"x-apifonws-date", date},
        {"content-type", "application/json"},
        {"accept", "application/json"}
      ],
      body: body
    )
  end

  @doc "Apifon's request signature."
  def signature(secret, method, path, body, date),
    do:
      :hmac
      |> :crypto.mac(:sha256, secret, Enum.join([method, path, body, date], "\n"))
      |> Base.encode64()

  defp accepted({:ok, %{body: %{} = body}}, outgoing) do
    case {get_in(body, ["result_info", "status_code"]), message_id(body["results"])} do
      {401, _id} -> {:error, {:unauthorized, "apifon_401"}}
      {code, _id} when is_integer(code) and code != 200 -> {:error, {:rejected, "apifon_#{code}"}}
      {_ok, id} when is_binary(id) -> {:ok, %{provider_message_id: id, cost_cents: nil, currency: nil}}
      {_ok, nil} -> {:error, {:uncertain, "apifon_unexpected_answer:" <> outgoing.id}}
    end
  end

  defp accepted({:ok, _unexpected}, _outgoing), do: {:error, {:uncertain, "apifon_unexpected_answer"}}
  defp accepted({:error, error}, _outgoing), do: {:error, http_error(error)}

  # `results` maps each number to its message (a list in Apifon's examples).
  defp message_id(%{} = results) do
    Enum.find_value(results, fn
      {_number, [%{"message_id" => id} | _rest]} when is_binary(id) -> id
      {_number, %{"message_id" => id}} when is_binary(id) -> id
      _other -> nil
    end)
  end

  defp message_id([%{"message_id" => id} | _rest]) when is_binary(id), do: id
  defp message_id(_results), do: nil

  defp http_error({kind, {:http, status}}), do: {kind, "apifon_#{status}"}
  defp http_error({:rejected, {:http, status, _detail}}), do: {:rejected, "apifon_#{status}"}
  defp http_error(other), do: other

  @impl true
  def check(%{account_id: token, secret: secret} = account)
      when is_binary(token) and is_binary(secret) do
    case signed_request(account, @balance_path, "") do
      {:ok, %{body: %{} = body}} -> {:ok, %{balance: body["balance"]}}
      {:ok, _other} -> {:ok, %{balance: nil}}
      {:error, error} -> {:error, http_error(error)}
    end
  end

  def check(_account), do: {:error, {:unauthorized, "apifon_credentials_missing"}}

  @impl true
  def parse_webhook(_account, %{params: %{"data" => data}}) when is_list(data),
    do: {:ok, Enum.flat_map(data, &event/1)}

  def parse_webhook(_account, %{params: %{"from" => from, "text" => text}})
      when is_binary(from) and is_binary(text),
      do: {:ok, [%{type: :inbound, channel: "sms", from: "+" <> String.trim_leading(from, "+"), text: text}]}

  def parse_webhook(_account, _request), do: {:ok, []}

  defp event(%{"message_id" => id, "status" => %{"code" => code} = status} = data)
       when is_binary(id) and is_integer(code) do
    [
      %{
        type: :status,
        provider_message_id: id,
        status: status(code),
        provider_status: status["text"] || Integer.to_string(code),
        error_code: error_code(code, data["error_code"]),
        cost_cents: nil,
        currency: nil,
        occurred_at: occurred_at(data["timestamp"]),
        event_key: "apifon:#{id}:#{code}"
      }
    ]
  end

  defp event(_data), do: []

  defp status(7), do: "delivered"
  defp status(code) when code in @failed_codes, do: "failed"
  defp status(_code), do: "sent"

  defp error_code(code, _error) when code not in @failed_codes, do: nil
  defp error_code(code, error) when error in [nil, "", "000"], do: "apifon_status_#{code}"
  defp error_code(_code, error), do: to_string(error)

  defp occurred_at(ts) when is_integer(ts) do
    case DateTime.from_unix(ts) do
      {:ok, at} -> %{at | microsecond: {0, 6}}
      _invalid -> nil
    end
  end

  defp occurred_at(_ts), do: nil

  defp base_url,
    do: Keyword.get(Application.get_env(:palee, __MODULE__, []), :base_url) || @default_base_url
end

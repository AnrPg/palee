defmodule Palee.Application.Channels.ChannelMessages do
  @moduledoc """
  Staff › «Μηνύματα SMS/Viber» (ADR-348/351): preview and send a message
  to a member or lead, the list of sent messages with their state and
  cost, sending a failed one again and stopping a queued one.
  """

  alias Palee.Application.Channels.SendThroughChannel
  alias Palee.Channels
  alias Palee.Channels.Domain.{CostPolicy, DeliveryPolicy, PhoneNumber}

  def preview(context, params, now \\ DateTime.utc_now()),
    do: SendThroughChannel.preview(context, staff(params), now)

  def send(context, params, now \\ DateTime.utc_now()),
    do: SendThroughChannel.call(context, staff(params), now)

  # Staff always send as staff; a missing key makes each click its own message.
  defp staff(params) do
    params
    |> Map.new(fn {key, value} -> {to_string(key), value} end)
    |> Map.put("source", "staff")
    |> Map.put_new_lazy("idempotency_key", fn -> "staff:" <> Ecto.UUID.generate() end)
  end

  @doc "Messages (newest first); filters `status`, `channel`, `contact_id`, `source_ref`."
  def list(context, params) do
    status = param(params, :status)
    channel = param(params, :channel)

    filters =
      %{
        status: if(status in DeliveryPolicy.statuses(), do: status),
        channel: if(channel in ~w(sms viber whatsapp), do: channel),
        contact_id: uuid(param(params, :contact_id)),
        source_ref: param(params, :source_ref),
        limit: integer(param(params, :limit)),
        offset: integer(param(params, :offset))
      }
      |> Map.reject(fn {_key, value} -> is_nil(value) end)

    context
    |> Channels.list_messages(filters)
    |> Map.update!(:messages, fn messages -> Enum.map(messages, &view/1) end)
  end

  def show(context, id) do
    case Channels.get_message(context, id) do
      nil ->
        {:error, :not_found}

      message ->
        {:ok,
         message
         |> view()
         |> Map.put(
           :events,
           Enum.map(
             message.events,
             &Map.take(&1, [:kind, :status, :provider_status, :error_code, :occurred_at])
           )
         )}
    end
  end

  def retry(context, id, now \\ DateTime.utc_now()) do
    with {:ok, message} <- Channels.retry(context, id, now) do
      SendThroughChannel.schedule(context, message)
      {:ok, view(message)}
    end
  end

  def cancel(context, id, now \\ DateTime.utc_now()) do
    with {:ok, message} <- Channels.cancel(context, id, Map.get(context, :user_id), now) do
      {:ok, view(message)}
    end
  end

  @public ~w(id contact_id channel purpose template_key locale body status hold_reason urgent
             attempts next_attempt_at provider account_mode segments estimated_cost_cents
             cost_cents currency error_code source source_ref created_by_id sent_at delivered_at
             failed_at inserted_at)a

  # ADR-369: the box sees its price, never the provider's: the charged
  # provider price comes back with the message's margin on it.
  defp view(message),
    do:
      message
      |> Map.take(@public)
      |> Map.put(:to, PhoneNumber.mask(message.to_phone))
      |> Map.put(:cost_cents, message.cost_cents && CostPolicy.counted(message))

  defp uuid(nil), do: nil

  defp uuid(value) do
    case Ecto.UUID.cast(value) do
      {:ok, id} -> id
      :error -> nil
    end
  end

  defp integer(value) when is_integer(value) and value >= 0, do: value

  defp integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} when number >= 0 -> number
      _other -> nil
    end
  end

  defp integer(_value), do: nil

  defp param(params, key) when is_map(params),
    do: Map.get(params, key, Map.get(params, Atom.to_string(key)))
end

defmodule Palee.Channels.Domain.DeliveryPolicy do
  @moduledoc """
  The outbox's states and retries (ADR-348 §5).

      queued ──claim──▶ sending ──provider accepted──▶ sent ──receipt──▶ delivered
         ▲                 │                              │
         └──transient──────┘                              └──receipt──▶ failed
                           └──refused / out of attempts / uncertain──▶ failed

  `cancelled` is a queued message staff stopped, or one whose consent was
  withdrawn before it left (checked again at send time).

  A transient error (network, 429, 5xx, refused credentials) is retried
  with growing waits up to `max_attempts/0`. A call that may have reached
  the provider without an answer (a timeout) is not sent again: the
  message fails as `delivery_uncertain`, so nobody gets it twice; staff
  may send it again.
  """

  @max_attempts 5
  @backoff_seconds [60, 300, 900, 3_600]
  @claim_timeout_seconds 300

  def max_attempts, do: @max_attempts
  def claim_timeout_seconds, do: @claim_timeout_seconds

  @statuses ~w(queued sending sent delivered failed cancelled)
  def statuses, do: @statuses

  @doc """
  The changes after one call to the provider. `result` is
  `{:ok, %{provider_message_id, cost_cents, currency}}` or
  `{:error, {:rejected | :unauthorized | :transient | :uncertain, detail}}`.
  """
  def outcome(message, {:ok, receipt}, %DateTime{} = now) do
    %{
      status: "sent",
      provider_message_id: receipt.provider_message_id,
      sent_at: now,
      hold_reason: nil,
      claimed_at: nil,
      next_attempt_at: nil,
      error_code: nil,
      error_message: nil
    }
    |> put_cost(receipt, message)
  end

  def outcome(_message, {:error, {:rejected, detail}}, now),
    do: failed("provider_rejected", detail, now)

  def outcome(_message, {:error, {:uncertain, detail}}, now),
    do: failed("delivery_uncertain", detail, now)

  def outcome(message, {:error, {kind, detail}}, now) when kind in [:unauthorized, :transient] do
    code = if kind == :unauthorized, do: "credentials_rejected", else: "provider_unavailable"

    if message.attempts >= @max_attempts do
      failed(code, detail, now)
    else
      %{
        status: "queued",
        claimed_at: nil,
        next_attempt_at: DateTime.add(now, backoff(message.attempts), :second),
        error_code: code,
        error_message: text(detail)
      }
    end
  end

  def outcome(message, {:error, other}, now), do: outcome(message, {:error, {:transient, other}}, now)

  defp put_cost(changes, %{cost_cents: cents} = receipt, _message) when is_integer(cents),
    do: Map.merge(changes, %{cost_cents: cents, currency: receipt[:currency] || "EUR"})

  defp put_cost(changes, _receipt, _message), do: changes

  defp failed(code, detail, now),
    do: %{
      status: "failed",
      failed_at: now,
      claimed_at: nil,
      next_attempt_at: nil,
      error_code: code,
      error_message: text(detail)
    }

  @doc "Seconds to wait after the `attempt`-th failed call."
  def backoff(attempt) when attempt >= 1,
    do: Enum.at(@backoff_seconds, attempt - 1, List.last(@backoff_seconds))

  def backoff(_attempt), do: hd(@backoff_seconds)

  @doc "What one attempt row records."
  def attempt_status({:ok, _receipt}), do: "sent"
  def attempt_status({:error, {:rejected, _}}), do: "rejected"
  def attempt_status({:error, {:unauthorized, _}}), do: "unauthorized"
  def attempt_status({:error, {:uncertain, _}}), do: "uncertain"
  def attempt_status({:error, _other}), do: "transient"

  @doc """
  The changes a delivery receipt brings, or nil when it changes nothing
  (an older state, or the message already final). Receipts may arrive out
  of order: `delivered` and `failed` are final, `sent` never goes back.
  """
  def receipt(message, %{status: status} = event, %DateTime{} = now) do
    cond do
      message.status in ~w(delivered failed cancelled) ->
        nil

      status == "delivered" ->
        %{status: "delivered", delivered_at: event[:occurred_at] || now}
        |> put_cost(event, message)

      status == "failed" ->
        %{
          status: "failed",
          failed_at: event[:occurred_at] || now,
          error_code: event[:error_code] || "undeliverable",
          error_message: nil
        }
        |> put_cost(event, message)

      status == "sent" and message.status in ~w(queued sending) ->
        %{status: "sent", sent_at: event[:occurred_at] || now}

      true ->
        if is_integer(event[:cost_cents]), do: put_cost(%{}, event, message)
    end
  end

  @doc "Staff may send again a failed message, or cancel a queued one."
  def retryable?(%{status: "failed"}), do: true
  def retryable?(_message), do: false

  def cancellable?(%{status: "queued"}), do: true
  def cancellable?(_message), do: false

  def retry(%DateTime{} = now),
    do: %{
      status: "queued",
      attempts: 0,
      next_attempt_at: now,
      provider_message_id: nil,
      failed_at: nil,
      error_code: nil,
      error_message: nil,
      hold_reason: nil
    }

  defp text(nil), do: nil
  defp text(detail) when is_binary(detail), do: String.slice(detail, 0, 500)
  defp text(detail), do: detail |> inspect() |> String.slice(0, 500)
end

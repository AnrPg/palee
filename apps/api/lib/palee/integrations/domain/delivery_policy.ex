defmodule Palee.Integrations.Domain.DeliveryPolicy do
  @moduledoc """
  When a webhook is sent again and when Palee gives up (ADR-379).

    * Any 2xx is delivered. 410 Gone means the receiver closed the endpoint:
      the delivery fails and the endpoint is switched off. Every other answer,
      a timeout or a refused connection is retried.
    * Retries follow a fixed schedule (about three days in all), so a
      receiver that was down over a weekend still gets everything, in order
      of the original events.
    * An endpoint whose last #{20} deliveries all failed for good is switched
      off (`too_many_failures`); the owner sees it and switches it on again.

  Pure: `now` is passed in.
  """

  # Seconds after attempt N (1-based) before attempt N + 1.
  @schedule [60, 300, 1_800, 7_200, 21_600, 43_200, 86_400, 86_400]
  @max_attempts length(@schedule) + 1
  @disable_after 20
  @lease_seconds 120
  @batch 25

  def max_attempts, do: @max_attempts
  def disable_after, do: @disable_after
  def lease_seconds, do: @lease_seconds
  def batch, do: @batch
  def schedule, do: @schedule

  @type outcome :: :succeeded | :gone | :failed | :blocked

  @doc "Sorts an HTTP answer or a transport error."
  @spec classify({:ok, integer()} | {:error, term()}) :: outcome()
  def classify({:ok, status}) when status in 200..299, do: :succeeded
  def classify({:ok, 410}), do: :gone
  def classify({:ok, _status}), do: :failed
  def classify({:error, :blocked_address}), do: :blocked
  def classify({:error, _reason}), do: :failed

  @doc """
  The delivery's next state after attempt number `attempt` ended with
  `outcome`: `{:succeeded, nil}`, `{:pending, next_attempt_at}` or
  `{:failed, nil}`.
  """
  def after_attempt(:succeeded, _attempt, _now), do: {:succeeded, nil}
  def after_attempt(:gone, _attempt, _now), do: {:failed, nil}
  def after_attempt(:blocked, _attempt, _now), do: {:failed, nil}

  def after_attempt(:failed, attempt, %DateTime{} = now) when attempt < @max_attempts do
    {:pending, DateTime.add(now, Enum.at(@schedule, attempt - 1), :second)}
  end

  def after_attempt(:failed, _attempt, _now), do: {:failed, nil}

  @doc """
  The endpoint's change after a delivery ended: `:healthy` resets its
  failure count, `{:disable, reason}` switches it off, `:count` adds one.
  """
  def endpoint_after(:succeeded, _consecutive), do: :healthy
  def endpoint_after(:gone, _consecutive), do: {:disable, "gone"}
  def endpoint_after(:blocked, _consecutive), do: {:disable, "blocked_address"}

  def endpoint_after(:failed, consecutive) when consecutive + 1 >= @disable_after,
    do: {:disable, "too_many_failures"}

  def endpoint_after(:failed, _consecutive), do: :count
end

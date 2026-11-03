defmodule Palee.Programmes.Domain.RefundRules do
  @moduledoc """
  What a buyer gets back when they give up a programme (ADR-371), pure.

  A programme is a service delivered over weeks, bought at a distance. Two
  layers apply, and the buyer gets the larger amount:

    * **Withdrawal (the law).** Where the seller's country gives a right of
      withdrawal (EU, EEA, UK: `Payments.Domain.Withdrawal.applies?/1`),
      the buyer may withdraw within 14 days of buying. A programme that has
      not started is refunded in full; one the buyer asked to start at once
      (`start_now`, recorded with its text hash) is refunded less the part
      already provided, in proportion to its days (Directive 2011/83/EU
      art. 9, 14(3), 16(a); the same rule as packages, ADR-248).
    * **The seller's rule** (`refund_policy`, chosen per programme and
      copied onto each purchase, so a later change never reaches past
      buyers):
      - `withdrawal_only`: nothing beyond the law;
      - `before_start`: a full refund any time before the start date;
      - `pro_rata`: also after 14 days, the days not yet reached.

  Staff can always refund more by hand (goodwill), never more than what is
  left of the price.

  The wording is a draft for legal review.
  """

  @policies ~w(before_start withdrawal_only pro_rata)
  @start_window_days 60

  def policies, do: @policies
  def start_window_days, do: @start_window_days

  @doc """
  Checks the start date a buyer chose: from today up to
  #{@start_window_days} days ahead.
  """
  def check_start(%Date{} = starts_on, %Date{} = today) do
    diff = Date.diff(starts_on, today)
    if diff >= 0 and diff <= @start_window_days, do: :ok, else: {:error, :invalid_start_date}
  end

  def check_start(_starts_on, _today), do: {:error, :invalid_start_date}

  @doc "The last day of a programme of `weeks` starting on `starts_on`."
  def ends_on(%Date{} = starts_on, weeks) when is_integer(weeks) and weeks > 0,
    do: Date.add(starts_on, weeks * 7 - 1)

  @doc """
  How much of the price the buyer gets back at `today`, and under which
  rule: `{:ok, %{amount_cents, rule}}` (`rule`: `withdrawal`,
  `before_start` or `pro_rata`), or `{:error, :programme_refund_not_available}`.

  `purchase` needs `status`, `price_cents`, `refunded_cents`,
  `refund_policy`, `starts_on`, `ends_on` and `withdrawal` (the record
  made at purchase: `applies`, `deadline`).
  """
  def quote(%{status: "active"} = purchase, %Date{} = today, %DateTime{} = now) do
    left = purchase.price_cents - (purchase.refunded_cents || 0)

    [withdrawal(purchase, today, now), seller(purchase, today)]
    |> Enum.reject(&is_nil/1)
    |> Enum.map(fn {rule, cents} -> {rule, min(cents, left)} end)
    |> Enum.filter(fn {_rule, cents} -> cents > 0 end)
    |> Enum.max_by(fn {_rule, cents} -> cents end, fn -> nil end)
    |> case do
      nil -> {:error, :programme_refund_not_available}
      {rule, cents} -> {:ok, %{amount_cents: cents, rule: rule}}
    end
  end

  def quote(_purchase, _today, _now), do: {:error, :programme_refund_not_available}

  defp withdrawal(
         %{withdrawal: %{"applies" => true, "deadline" => deadline}} = purchase,
         today,
         now
       ) do
    with {:ok, at, _offset} <- DateTime.from_iso8601(deadline),
         true <- DateTime.compare(now, at) != :gt do
      {"withdrawal", unused_cents(purchase, today)}
    else
      _closed -> nil
    end
  end

  defp withdrawal(_purchase, _today, _now), do: nil

  defp seller(%{refund_policy: "before_start"} = purchase, today) do
    if Date.compare(today, purchase.starts_on) == :lt,
      do: {"before_start", purchase.price_cents},
      else: nil
  end

  defp seller(%{refund_policy: "pro_rata"} = purchase, today) do
    if Date.compare(today, purchase.ends_on) != :gt,
      do: {"pro_rata", unused_cents(purchase, today)},
      else: nil
  end

  defp seller(_purchase, _today), do: nil

  @doc """
  The price less the part already provided: the days from the start up to
  (not including) `today`, over all the programme's days.
  """
  def unused_cents(%{price_cents: price, starts_on: starts, ends_on: ends}, %Date{} = today) do
    total = Date.diff(ends, starts) + 1
    used = Date.diff(today, starts) |> max(0) |> min(total)
    max(price - round(price * used / total), 0)
  end

  @doc """
  Whether a staff refund of `amount_cents` fits what is left of the price.
  """
  def check_staff_amount(purchase, amount_cents) do
    left = purchase.price_cents - (purchase.refunded_cents || 0)

    cond do
      purchase.status not in ["active", "completed"] -> {:error, :programme_refund_not_available}
      not (is_integer(amount_cents) and amount_cents > 0) -> {:error, :invalid_refund_amount}
      amount_cents > left -> {:error, :refund_exceeds_remaining}
      true -> :ok
    end
  end
end

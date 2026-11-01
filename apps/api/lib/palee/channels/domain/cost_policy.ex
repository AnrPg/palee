defmodule Palee.Channels.Domain.CostPolicy do
  @moduledoc """
  What a message costs the box and the monthly budget cap (ADR-349 §3).
  Money is integer cents in the connection's currency.

  Before a message is queued its cost is estimated from a price list (per
  channel, purpose and destination country; per SMS part). The provider's
  receipt replaces the estimate with the price it charged, when it sends
  one. A message is refused when the month's spend plus its estimate would
  pass the cap; a cap of 0 stops every message.

  ADR-369: on Palee's own provider account the box pays the provider's
  price plus Palee's margin (`price/2`); the estimate, the budget cap and the
  month's spend are all in that box price. The provider's own price is kept
  beside it for the Palee team only.

  The default prices are public list prices for Greece and Cyprus in
  October 2026 (see ADR-349 for the sources), rounded up to whole cents;
  `config :palee, :channel_prices` replaces them.
  """

  # {channel, purpose} => %{country | :default => cents per part/message}
  @default_prices %{
    {"sms", "service"} => %{"GR" => 7, "CY" => 7, default: 9},
    {"sms", "marketing"} => %{"GR" => 7, "CY" => 7, default: 9},
    {"viber", "service"} => %{"GR" => 2, "CY" => 2, default: 3},
    {"viber", "marketing"} => %{"GR" => 3, "CY" => 3, default: 4},
    {"whatsapp", "service"} => %{"GR" => 3, "CY" => 3, default: 4},
    {"whatsapp", "marketing"} => %{"GR" => 9, "CY" => 9, default: 10}
  }

  def default_prices, do: @default_prices

  # ADR-369: margins in basis points (1 bps = 0.01 %), per channel.
  @margin_channels ~w(email sms viber whatsapp)
  @max_margin_bps 100_000

  @doc "Channels Palee may put a margin on."
  def margin_channels, do: @margin_channels

  @doc "The largest margin the Palee team may set (1000 %)."
  def max_margin_bps, do: @max_margin_bps

  @doc """
  The box's price for a message the provider charges `provider_cents` for,
  with Palee's margin of `margin_bps` (ADR-369): whole cents, rounded up, so
  a margin never rounds to nothing. Own-account messages carry no margin
  (`margin_bps` 0) and cost exactly the provider's price.
  """
  def price(provider_cents, margin_bps)
      when is_integer(provider_cents) and provider_cents >= 0 and is_integer(margin_bps) and
             margin_bps >= 0,
      do: div(provider_cents * (10_000 + margin_bps) + 9_999, 10_000)

  @doc "The margin on `channel` from the platform's margins (0 when unset)."
  def margin_bps(margins, channel) when is_map(margins) do
    case Map.get(margins, channel) do
      bps when is_integer(bps) and bps >= 0 -> bps
      _unset -> 0
    end
  end

  def margin_bps(_margins, _channel), do: 0

  @doc """
  Validates the margins the Palee team saves: `{:ok, margins}` with every
  channel (missing ones 0) or `{:error, {:invalid_fields, errors}}`.
  """
  def validate_margins(params) when is_map(params) do
    params = Map.new(params, fn {key, value} -> {to_string(key), value} end)

    errors =
      params
      |> Enum.reject(fn {channel, bps} ->
        channel in @margin_channels and is_integer(bps) and bps >= 0 and bps <= @max_margin_bps
      end)
      |> Map.new(fn {channel, _bps} -> {channel, "invalid"} end)

    if errors == %{},
      do: {:ok, Map.merge(Map.new(@margin_channels, &{&1, 0}), params)},
      else: {:error, {:invalid_fields, errors}}
  end

  def validate_margins(_params), do: {:error, {:invalid_fields, %{margins_bps: "invalid"}}}

  @doc "Estimated cents for a message of `segments` parts."
  def estimate(prices, channel, purpose, country, segments) do
    table = Map.get(prices || @default_prices, {channel, purpose}) || %{default: 10}
    per_part = Map.get(table, country) || Map.get(table, :default, 10)
    per_part * segments
  end

  @doc """
  `:ok` or `{:error, :channel_budget_exceeded}` for a message costing
  `estimate` when `spent` is already used this month.
  """
  def within_budget(spent, estimate, cap)
      when is_integer(spent) and is_integer(estimate) and is_integer(cap) do
    if spent + estimate <= cap, do: :ok, else: {:error, :channel_budget_exceeded}
  end

  @doc "The month (box clock) `now` falls in, as a UTC range `{from, to}`."
  def month_range(%DateTime{} = now, zone) do
    local = DateTime.shift_zone!(now, zone)
    first = Date.beginning_of_month(DateTime.to_date(local))
    next = first |> Date.end_of_month() |> Date.add(1)
    {midnight(first, zone), midnight(next, zone)}
  end

  @doc "The UTC range of a month given as `YYYY-MM` on the box clock."
  def month_range_of(<<year::binary-size(4), "-", month::binary-size(2)>>, zone) do
    with {y, ""} <- Integer.parse(year),
         {m, ""} when m in 1..12 <- Integer.parse(month),
         {:ok, first} <- Date.new(y, m, 1) do
      next = first |> Date.end_of_month() |> Date.add(1)
      {:ok, {midnight(first, zone), midnight(next, zone)}}
    else
      _invalid -> {:error, :invalid_month}
    end
  end

  def month_range_of(_month, _zone), do: {:error, :invalid_month}

  defp midnight(date, zone) do
    naive = NaiveDateTime.new!(date, ~T[00:00:00])

    case DateTime.from_naive(naive, zone) do
      {:ok, at} -> DateTime.shift_zone!(at, "Etc/UTC")
      {:ambiguous, first, _second} -> DateTime.shift_zone!(first, "Etc/UTC")
      {:gap, _before, after_gap} -> DateTime.shift_zone!(after_gap, "Etc/UTC")
    end
  end

  @doc """
  What a message counts towards the box's month: the provider's charged
  price with the margin of the message, else the estimated box price.
  """
  def counted(%{cost_cents: cents} = message) when is_integer(cents),
    do: price(cents, Map.get(message, :margin_bps) || 0)

  def counted(%{estimated_cost_cents: cents}), do: cents
end

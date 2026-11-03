defmodule Palee.Payments.Domain.SurchargePolicy do
  @moduledoc """
  CP-A5 (ADR-340): the box's choice to pass the card fee on to the person
  paying, and what it adds to one payment, pure. The law of the box's
  country (`SurchargeLaw`) always wins over the box's choice.

  Settings (one per box, every key with a default):

    * `enabled` – off by default: nobody pays a surcharge until the owner
      turns it on;
    * `channels` – where it applies: `online` (a member's card online:
      a saved card whose kind is known), `terminal` (Tap to Pay at the
      desk: the provider applies its own legal surcharge per card) and
      `desk` (a card on the box's own card machine, `card_manual`);
    * `percent_bps` (basis points of the price, 0–1000) and `fixed_cents`
      (0–10000): the surcharge is `price × percent + fixed`, never more
      than the law's cap (`cap_bps` of the price);
    * `region_code` – the state or province (ISO 3166-2), where the law
      differs inside the country (US, Canada);
    * `at_cost_confirmed` – the owner confirms the surcharge is no more
      than what accepting the card costs, where the law asks so.

  A quote is what the person is shown before paying: `applies`,
  `surcharge_cents`, `total_cents` and, when nothing is added, `reason`.
  """

  alias Palee.Payments.Domain.SurchargeLaw

  @channels ~w(online terminal desk)
  @max_percent_bps 1_000
  @max_fixed_cents 10_000

  def channels, do: @channels

  @doc "The stored settings with every missing key at its default."
  def resolve(nil), do: resolve(%{})

  def resolve(settings) when is_map(settings) do
    %{
      enabled: get(settings, :enabled) == true,
      channels: (get(settings, :channels) || []) |> Enum.filter(&(&1 in @channels)),
      percent_bps: integer(get(settings, :percent_bps)),
      fixed_cents: integer(get(settings, :fixed_cents)),
      region_code: get(settings, :region_code),
      at_cost_confirmed: get(settings, :at_cost_confirmed) == true
    }
  end

  @doc """
  Applies a change, checked against the law of `country` on `date`.
  Returns `{:ok, settings}`, `{:error, {:invalid_fields, errors}}` or, when
  the law forbids what was asked, `{:error, :card_surcharge_not_allowed,
  details}`.
  """
  def change(current, params, country, %Date{} = date) when is_map(params) do
    base = resolve(current)
    params = Map.new(params, fn {key, value} -> {to_string(key), value} end)

    {settings, errors} =
      Enum.reduce(params, {base, %{}}, fn {key, value}, {acc, errors} ->
        case cast(key, value) do
          {:ok, field, cast} -> {Map.put(acc, field, cast), errors}
          {:error, code} -> {acc, Map.put(errors, key, code)}
        end
      end)

    errors =
      if settings.enabled and settings.channels != [] and settings.percent_bps == 0 and
           settings.fixed_cents == 0 and settings.channels != ["terminal"],
         do: Map.put(errors, "percent_bps", "required"),
         else: errors

    regime = SurchargeLaw.regime(country, settings.region_code, date)

    cond do
      errors != %{} -> {:error, {:invalid_fields, errors}}
      not settings.enabled -> {:ok, settings}
      true -> lawful(settings, regime)
    end
  end

  def change(_current, _params, _country, _date),
    do: {:error, {:invalid_fields, %{"surcharge" => "invalid"}}}

  defp lawful(settings, regime) do
    cond do
      regime.region_required ->
        {:error, {:invalid_fields, %{"region_code" => "required"}}}

      not SurchargeLaw.allowed?(regime) ->
        {:error, :card_surcharge_not_allowed, details(regime)}

      is_integer(regime.cap_bps) and settings.percent_bps > regime.cap_bps ->
        {:error, :card_surcharge_not_allowed, Map.put(details(regime), :reason, "above_cap")}

      regime.at_cost and not settings.at_cost_confirmed ->
        {:error, {:invalid_fields, %{"at_cost_confirmed" => "required"}}}

      true ->
        {:ok, settings}
    end
  end

  @doc "What the law allows, for the owner's settings page and refusals."
  def details(regime) do
    %{
      regime: regime.code,
      rule: Atom.to_string(regime.rule),
      cap_bps: regime.cap_bps,
      at_cost: regime.at_cost,
      region_required: regime.region_required
    }
  end

  @doc """
  What `channel` adds to a price of `base_cents` for `card` (`funding`,
  `country`, `commercial`; an empty map for a card not chosen yet). Not
  for `terminal`, where the provider applies its own surcharge.
  """
  def quote(settings, regime, channel, base_cents, card)
      when channel in ["online", "desk"] and is_integer(base_cents) and base_cents >= 0 do
    settings = resolve(settings)

    reason =
      cond do
        not settings.enabled -> "off"
        channel not in settings.channels -> "channel_off"
        not SurchargeLaw.allowed?(regime) -> "not_allowed_here"
        card == %{} and not SurchargeLaw.unknown_card_allowed?(regime) -> "card_unknown"
        not SurchargeLaw.card_allowed?(regime, card) -> "card_not_surchargeable"
        true -> nil
      end

    surcharge = if is_nil(reason), do: amount(settings, regime, base_cents), else: 0

    %{
      applies: surcharge > 0,
      surcharge_cents: surcharge,
      total_cents: base_cents + surcharge,
      percent_bps: settings.percent_bps,
      fixed_cents: settings.fixed_cents,
      reason: if(surcharge > 0, do: nil, else: reason || "zero"),
      rule: Atom.to_string(regime.rule)
    }
  end

  @doc "The surcharge of a price: percent plus fixed, within the law's cap."
  def amount(settings, regime, base_cents) do
    raw = div(base_cents * settings.percent_bps + 5_000, 10_000) + settings.fixed_cents

    case regime.cap_bps do
      cap when is_integer(cap) -> min(raw, div(base_cents * cap, 10_000))
      nil -> raw
    end
  end

  @doc """
  ADR-340: whether Tap to Pay asks the provider to skip its surcharge.
  With no saved settings the provider decides (as before ADR-340); once
  the owner chose, «off» or a country that forbids it skips it.
  """
  def terminal_skip?(nil, _regime), do: false

  def terminal_skip?(settings, regime) do
    settings = resolve(settings)

    not (settings.enabled and "terminal" in settings.channels and
           SurchargeLaw.allowed?(regime))
  end

  @doc """
  Checks a surcharge staff typed for a card on the box's own machine:
  the card must allow one and it may not exceed the quote.
  """
  def check_desk(settings, regime, base_cents, surcharge_cents, card)
      when is_integer(surcharge_cents) and surcharge_cents > 0 do
    quote = quote(settings, regime, "desk", base_cents, card)

    cond do
      not quote.applies ->
        {:error, :card_surcharge_not_allowed, %{reason: quote.reason, rule: quote.rule}}

      surcharge_cents > quote.surcharge_cents ->
        {:error, :card_surcharge_not_allowed,
         %{reason: "above_quote", max_cents: quote.surcharge_cents, rule: quote.rule}}

      true ->
        :ok
    end
  end

  def check_desk(_settings, _regime, _base, _surcharge, _card),
    do: {:error, {:invalid_fields, %{"surcharge_cents" => "invalid"}}}

  defp cast("enabled", value) when is_boolean(value), do: {:ok, :enabled, value}

  defp cast("channels", values) when is_list(values) do
    if Enum.all?(values, &(&1 in @channels)),
      do: {:ok, :channels, values |> Enum.uniq() |> Enum.sort()},
      else: {:error, "invalid"}
  end

  defp cast("percent_bps", value)
       when is_integer(value) and value >= 0 and value <= @max_percent_bps,
       do: {:ok, :percent_bps, value}

  defp cast("fixed_cents", value)
       when is_integer(value) and value >= 0 and value <= @max_fixed_cents,
       do: {:ok, :fixed_cents, value}

  defp cast("region_code", nil), do: {:ok, :region_code, nil}

  defp cast("region_code", value) when is_binary(value) do
    value = value |> String.trim() |> String.upcase()

    cond do
      value == "" -> {:ok, :region_code, nil}
      value =~ ~r/^[A-Z]{2}-[A-Z0-9]{1,3}$/ -> {:ok, :region_code, value}
      true -> {:error, "invalid"}
    end
  end

  defp cast("at_cost_confirmed", value) when is_boolean(value),
    do: {:ok, :at_cost_confirmed, value}

  defp cast(key, _value) when key in ~w(enabled channels percent_bps fixed_cents region_code
                                         at_cost_confirmed),
    do: {:error, "invalid"}

  defp cast(_key, _value), do: {:error, "unknown"}

  defp integer(value) when is_integer(value) and value >= 0, do: value
  defp integer(_value), do: 0

  defp get(map, key), do: Map.get(map, key, Map.get(map, to_string(key)))
end

defmodule Palee.Payments.Domain.SurchargeLaw do
  @moduledoc """
  CP-A5 (ADR-340): where a business may pass the card fee on to the person
  paying, and on which cards, pure. Research of 2026-10-31; a country Palee
  has not researched gets `:none`, so a surcharge is refused rather than
  risked.

  `rule` says which cards may carry a surcharge:

    * `:eea_non_consumer` – EU and EEA (PSD2 art. 62(4), Directive (EU)
      2015/2366): no surcharge on cards whose interchange is capped by the
      IFR (Regulation (EU) 2015/751), i.e. consumer debit and credit cards
      issued in the EEA. Commercial cards and cards issued outside the EEA
      may carry one, at no more than the cost of accepting them;
    * `:commercial_only` – the United Kingdom (Consumer Rights (Payment
      Surcharges) Regulations 2012, as amended by the Payment Services
      Regulations 2017): no surcharge on any consumer card; commercial
      cards at cost;
    * `:credit_only` – the United States and Canada: credit cards only
      (never debit or prepaid: Durbin Amendment and the card networks'
      rules), within the network cap (Visa US 3 %, Canada 2.4 %), and not
      in the states or provinces that ban surcharging;
    * `:any` – every card, at cost (Australia before 1 October 2026);
    * `:none` – no surcharge (Australia from 1 October 2026, the US states
      and Canadian province that ban it, an unknown country).

  `at_cost`: the surcharge must not exceed what accepting the card costs
  the business, which only the business knows: Palee asks it to confirm
  (`at_cost_confirmed`) and also caps it at `cap_bps` of the price.
  """

  @eea ~w(AT BE BG HR CY CZ DK EE FI FR DE GR HU IE IT LV LT LU MT NL PL PT RO SK SI ES SE
          IS LI NO)
  # A surcharge "at cost" above 3 % of the price is not a realistic card fee.
  @at_cost_ceiling_bps 300
  @us_cap_bps 300
  @us_banned ~w(US-CT US-MA)
  @us_caps %{"US-CO" => 200}
  @ca_cap_bps 240
  @ca_banned ~w(CA-QC)
  @au_ban_from ~D[2026-10-01]

  @sources %{
    "eea" => [
      "https://eur-lex.europa.eu/eli/dir/2015/2366/oj",
      "https://eur-lex.europa.eu/eli/reg/2015/751/oj"
    ],
    "uk" => [
      "https://www.legislation.gov.uk/uksi/2012/3110",
      "https://www.legislation.gov.uk/uksi/2017/752/schedule/8"
    ],
    "us" => [
      "https://malegislature.gov/Laws/GeneralLaws/PartI/TitleXX/Chapter140D/Section28A",
      "https://www.nickel.com/surcharge-laws"
    ],
    "ca" => [
      "https://www.canada.ca/en/financial-consumer-agency/services/merchants/credit-fees-merchant.html",
      "https://www.mastercard.com/ca/en/business/support/merchant-surcharge-rules.html"
    ],
    "au" => ["https://rba.gov.au/media-releases/2026/mr-26-10.html"]
  }

  def eea, do: @eea
  def eea?(country), do: country in @eea

  @doc """
  The rules for a business in `country` (ISO 3166-1 alpha-2) and, where
  they differ inside it, `region` (ISO 3166-2, e.g. `US-CO`), on `date`.
  """
  def regime(country, region, %Date{} = date) do
    country = upcase(country)
    region = upcase(region)

    cond do
      country in @eea -> regime("eea", :eea_non_consumer, @at_cost_ceiling_bps, true)
      country == "GB" -> regime("uk", :commercial_only, @at_cost_ceiling_bps, true)
      country == "US" -> north_america("us", region, @us_banned, @us_caps, @us_cap_bps)
      country == "CA" -> north_america("ca", region, @ca_banned, %{}, @ca_cap_bps)
      country == "AU" -> australia(date)
      true -> regime("unknown", :none, nil, false)
    end
  end

  defp north_america(code, region, banned, caps, cap) do
    cond do
      not (is_binary(region) and String.starts_with?(region, String.upcase(code) <> "-")) ->
        code |> regime(:none, nil, false) |> Map.put(:region_required, true)

      region in banned ->
        regime(code, :none, nil, false)

      true ->
        regime(code, :credit_only, Map.get(caps, region, cap), false)
    end
  end

  defp australia(date) do
    if Date.compare(date, @au_ban_from) == :lt,
      do: regime("au", :any, @at_cost_ceiling_bps, true),
      else: regime("au", :none, nil, false)
  end

  defp regime(code, rule, cap_bps, at_cost) do
    %{
      code: code,
      rule: rule,
      cap_bps: cap_bps,
      at_cost: at_cost,
      region_required: false,
      sources: Map.get(@sources, code, [])
    }
  end

  @doc "Whether any card may ever carry a surcharge under `regime`."
  def allowed?(%{rule: :none}), do: false
  def allowed?(%{rule: _rule}), do: true

  @doc """
  Whether a card may carry a surcharge. `card`: `funding` (`credit`,
  `debit`, `prepaid` or nil), `country` (issuing country or nil) and
  `commercial` (true, false or nil). What Palee does not know about the
  card counts against the surcharge.
  """
  def card_allowed?(%{rule: :any}, _card), do: true
  def card_allowed?(%{rule: :none}, _card), do: false

  def card_allowed?(%{rule: :commercial_only}, card), do: field(card, :commercial) == true

  def card_allowed?(%{rule: :eea_non_consumer}, card) do
    country = upcase(field(card, :country))

    field(card, :commercial) == true or
      (is_binary(country) and byte_size(country) == 2 and country not in @eea)
  end

  def card_allowed?(%{rule: :credit_only}, card), do: field(card, :funding) == "credit"

  @doc "Whether a card Palee knows nothing about may carry a surcharge."
  def unknown_card_allowed?(regime), do: card_allowed?(regime, %{})

  defp field(card, key) when is_map(card), do: Map.get(card, key) || Map.get(card, to_string(key))
  defp field(_card, _key), do: nil

  defp upcase(value) when is_binary(value), do: value |> String.trim() |> String.upcase()
  defp upcase(_value), do: nil
end

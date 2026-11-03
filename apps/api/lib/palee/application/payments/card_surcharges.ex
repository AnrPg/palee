defmodule Palee.Application.Payments.CardSurcharges do
  @moduledoc """
  CP-A5 (ADR-340): the box passes the card fee on to the person paying,
  where the law of its country allows it, and nowhere else.

    * The owner's settings are checked against `SurchargeLaw` for the
      box's country (its fiscal identity) and state or province on save;
      what the law forbids is refused, never silently stored.
    * **Online**: Palee adds the surcharge only when it knows the card is
      one the law allows it on: a saved card whose provider told whether it
      is credit or debit, commercial, and where it was issued. A card the
      member has not chosen yet never carries one (it could be a consumer
      card). The member sees the quote before paying.
    * **Tap to Pay**: the provider applies its own lawful surcharge per
      card (ADR-264); the owner's «off» asks it to skip it.
    * **Desk card machine** (`card_manual`): staff type the surcharge the
      machine added and the kind of card; Palee checks both.

  A surcharge is revenue of the sale (ADR-264): its own Finance stream sale
  (`card_surcharge`) and a line of the same receipt.
  """

  alias Palee.{Finance, Fiscal, Organizations, Payments}
  alias Palee.Payments.Domain.{SurchargeLaw, SurchargePolicy, TerminalSale}

  @doc "The settings with what the law of the box's country allows."
  def settings(context) do
    stored = Payments.surcharge_settings(context)
    settings = SurchargePolicy.resolve(stored)
    regime = regime(context, settings.region_code)

    %{
      settings: settings,
      saved: not is_nil(stored),
      country_code: country(context),
      law: regime |> SurchargePolicy.details() |> Map.put(:sources, regime.sources),
      allowed: SurchargeLaw.allowed?(regime),
      updated_at: stored && stored[:updated_at]
    }
  end

  @doc "Saves the owner's choice; refused where the law forbids it."
  def save(context, params) when is_map(params) do
    current = Payments.surcharge_settings(context)

    params = Map.new(params, fn {key, value} -> {to_string(key), value} end)

    params =
      if Map.has_key?(params, "region_code") or SurchargePolicy.resolve(current).region_code,
        do: params,
        else: Map.put(params, "region_code", identity_region(context))

    with {:ok, settings} <-
           SurchargePolicy.change(current, params, country(context), today(context)),
         {:ok, _saved} <-
           Payments.save_surcharge_settings(context, settings, Map.get(context, :user_id)) do
      {:ok, settings(context)}
    end
  end

  @doc """
  What `channel` (`online` or `desk`) adds to `amount_cents` for a card
  (`funding`, `country`, `commercial`; empty when not chosen yet).
  """
  def quote(context, channel, amount_cents, card \\ %{})

  def quote(context, channel, amount_cents, card)
      when channel in ["online", "desk"] and is_integer(amount_cents) and amount_cents > 0 do
    settings = Payments.surcharge_settings(context)
    regime = regime(context, SurchargePolicy.resolve(settings).region_code)
    {:ok, SurchargePolicy.quote(settings, regime, channel, amount_cents, card || %{})}
  end

  def quote(_context, _channel, _amount_cents, _card),
    do: {:error, {:invalid_fields, %{"amount_cents" => "invalid"}}}

  @doc "The member's quote for paying `amount_cents` with one of their saved cards (or none)."
  def member_quote(context, amount_cents, nil), do: quote(context, "online", amount_cents, %{})

  def member_quote(context, amount_cents, method_id) do
    with {:ok, method} <- Payments.member_method(context, context.user_id, method_id) do
      quote(context, "online", amount_cents, card(method))
    end
  end

  @doc "The surcharge a saved card carries on `amount_cents` (0 when none)."
  def for_saved_card(context, method, amount_cents) do
    case quote(context, "online", amount_cents, card(method)) do
      {:ok, %{surcharge_cents: cents}} -> cents
      _error -> 0
    end
  end

  @doc "The card facts of a saved card, as the law reads them."
  def card(method) do
    %{
      funding: method[:card_funding],
      country: method[:card_country],
      commercial: method[:card_commercial]
    }
  end

  @doc "Whether Tap to Pay asks the provider to skip its surcharge."
  def terminal_skip?(context) do
    stored = Payments.surcharge_settings(context)
    regime = regime(context, SurchargePolicy.resolve(stored).region_code)
    SurchargePolicy.terminal_skip?(stored, regime)
  end

  @doc """
  Checks a surcharge staff record with a card paid on the box's own card
  machine. `card`: `funding`, `country`, `commercial` as staff read them.
  """
  def check_desk(context, amount_cents, surcharge_cents, card) do
    settings = Payments.surcharge_settings(context)
    regime = regime(context, SurchargePolicy.resolve(settings).region_code)
    SurchargePolicy.check_desk(settings, regime, amount_cents, surcharge_cents, card || %{})
  end

  @doc """
  Records a card surcharge as revenue (ADR-264): its own Finance stream
  sale, idempotent per its source (the intent, or the desk's payment).
  `sale` is the intent (or an intent-like map for the desk) and
  `user_id` the payer, nil for a walk-in.
  """
  def record(context, sale, user_id) do
    if TerminalSale.surcharge?(sale) do
      attrs =
        TerminalSale.surcharge(
          sale,
          membership(context, user_id),
          Organizations.local_today(context.organization_id, sale[:succeeded_at] || now()),
          labels(context)
        )

      case Finance.record_stream_sale(context, attrs) do
        {:ok, _recorded} -> :ok
        {:error, _reason} = error -> error
      end
    else
      :ok
    end
  end

  @doc "The surcharge's line on the sale's receipt (ADR-264)."
  def receipt_params(context, sale) do
    if TerminalSale.surcharge?(sale),
      do: %{
        "surcharge_cents" => sale.surcharge_cents,
        "surcharge_description" => labels(context).surcharge
      },
      else: %{}
  end

  @doc "Names printed on the business's documents, in its language."
  def labels(context) do
    case country(context) do
      "GR" -> %{surcharge: "Επιβάρυνση κάρτας"}
      _other -> %{surcharge: "Card surcharge"}
    end
  end

  defp membership(_context, nil), do: nil

  defp membership(context, user_id) do
    case Finance.get_member_profile(context, user_id) do
      %{membership: %{id: id}} -> %{membership_id: id, user_id: user_id}
      _none -> nil
    end
  end

  defp regime(context, region),
    do: SurchargeLaw.regime(country(context), region || identity_region(context), today(context))

  defp country(context) do
    case Fiscal.identity_status(context) do
      %{identity: %{country_code: code}} when is_binary(code) -> code
      _none -> nil
    end
  end

  # The state or province of the business's fiscal identity (ISO 3166-2).
  defp identity_region(context) do
    case Fiscal.identity_status(context) do
      %{identity: %{country_code: country, region: region}}
      when is_binary(country) and is_binary(region) and region != "" ->
        if String.contains?(region, "-"),
          do: String.upcase(region),
          else: String.upcase(country <> "-" <> region)

      _none ->
        nil
    end
  end

  defp today(context), do: Organizations.local_today(context.organization_id, now())

  defp now, do: DateTime.utc_now()
end

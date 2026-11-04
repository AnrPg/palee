defmodule Palee.Application.Programmes.Buying do
  @moduledoc """
  ADR-371 use cases for a buyer inside the seller's business: read the
  terms, buy a programme on the seller's own provider page, see what they
  bought with its WODs, withdraw or ask for the refund the rules give, and
  review it.

  Nothing is delivered before the provider confirms the money
  (`Programmes.Fulfilment`). The store apps never offer the purchase: a
  programme has only digital services (ADR-256, `canBuyHere`).
  """

  alias Palee.Application.Programmes.{Presenter, Studio, Terms}
  alias Palee.Application.PublicURL
  alias Palee.{Organizations, Payments, Programmes}

  def terms(context, id, language) do
    with {:ok, programme, version} <- for_sale(context, id) do
      applies = Terms.withdrawal_applies?(context)
      today = today(context)

      {:ok,
       %{
         programme: Presenter.public(programme, version),
         available: Payments.available?(context, "programmes"),
         provider: Payments.provider(context),
         earliest_start: today,
         latest_start: Date.add(today, 60),
         withdrawal_days: if(applies, do: Terms.days()),
         start_now_text: if(applies, do: Terms.start_now_text(language)),
         refund_rule: programme.refund_policy,
         refund_text: Terms.rule_text(programme.refund_policy, language),
         terms_version: Terms.version(),
         owned: owned_purchase(context, programme.id)
       }}
    end
  end

  @doc """
  Opens a checkout for programme `id`. `params`: `idempotency_key`,
  `starts_on` (default today, up to 60 days ahead), `start_now` (required
  where withdrawal applies), `language`.
  """
  def buy(context, id, params) do
    now = DateTime.utc_now()
    today = today(context, now)
    starts_on = params[:starts_on] || today
    language = Terms.language(params[:language])

    with {:ok, programme, version} <- for_sale(context, id),
         true <-
           Payments.available?(context, "programmes") || {:error, :online_payments_unavailable},
         true <-
           is_nil(owned_purchase(context, programme.id)) || {:error, :programme_already_owned},
         :ok <- Programmes.check_start(starts_on, today),
         true <- valid_key?(params[:idempotency_key]) || {:error, :idempotency_key_required},
         {:ok, withdrawal} <-
           Terms.record(
             Terms.withdrawal_applies?(context),
             %{
               start_now: params[:start_now],
               language: language,
               starts_on: starts_on,
               today: today
             },
             now
           ),
         {:ok, purchase} <-
           Programmes.create_purchase(context, %{
             programme_id: programme.id,
             version_id: version.id,
             user_id: context.user_id,
             price_cents: programme.price_cents,
             currency: programme.currency,
             refund_policy: programme.refund_policy,
             starts_on: starts_on,
             ends_on: Programmes.ends_on(starts_on, version.weeks),
             withdrawal: withdrawal,
             idempotency_key: params[:idempotency_key]
           }),
         true <- purchase.user_id == context.user_id || {:error, :duplicate_idempotency_key},
         {:ok, checkout} <- checkout(context, programme, purchase, language, now),
         {:ok, _purchase} <- attach(context, purchase, checkout) do
      {:ok, %{purchase_id: purchase.id, payment: checkout}}
    end
  end

  defp checkout(context, programme, purchase, language, now) do
    base = PublicURL.base_url() |> String.trim_trailing("/")

    Payments.start_checkout(
      context,
      %{
        purpose_type: "programme",
        purpose_id: purchase.id,
        user_id: context.user_id,
        amount_cents: purchase.price_cents,
        currency: purchase.currency,
        description: programme.title,
        customer: %{language: language},
        return_url: base <> "/pay/return?payment={payment_id}",
        cancel_url: base <> "/pay/return?payment={payment_id}&cancelled=1",
        save_method: false,
        metadata: %{"programme_id" => programme.id, "withdrawal" => purchase.withdrawal},
        idempotency_key: "programme:" <> purchase.idempotency_key,
        created_by_id: context.user_id
      },
      now
    )
  end

  defp attach(_context, %{payment_intent_id: id} = purchase, _checkout) when is_binary(id),
    do: {:ok, purchase}

  defp attach(context, purchase, %{id: intent_id}),
    do: Programmes.set_purchase_intent(context, purchase.id, intent_id)

  defp valid_key?(key), do: is_binary(key) and byte_size(key) in 8..180

  # ── What the buyer owns ─────────────────────────────────────────────────

  def mine(context) do
    now = DateTime.utc_now()
    today = today(context, now)

    purchases =
      Programmes.list_purchases(context, %{
        user_id: context.user_id,
        statuses: ~w(active completed withdrawn refunded)
      })

    titles =
      context
      |> Programmes.list_programmes(%{})
      |> Map.new(&{&1.id, &1.title})

    Enum.map(purchases, fn purchase ->
      Presenter.purchase(purchase, %{
        title: Map.get(titles, purchase.programme_id),
        refund: quote(purchase, today, now)
      })
    end)
  end

  def show(context, purchase_id) do
    now = DateTime.utc_now()
    today = today(context, now)

    with {:ok, purchase} <- own(context, purchase_id),
         %{} = version <-
           Programmes.get_version(context, purchase.version_id) || {:error, :not_found},
         %{} = programme <-
           Programmes.get_programme(context, purchase.programme_id) || {:error, :not_found} do
      days =
        Enum.map(version.days, fn row ->
          %{
            day: row["day"],
            # ADR-540: the buyer's moved date when they caught up on it.
            date: Programmes.purchase_day_date(purchase, row["day"]),
            workout_id: row["workout_id"],
            title: row["title"],
            summary: row["summary"]
          }
        end)

      review = Programmes.review_for_purchase(context, purchase.id)

      {:ok,
       Presenter.purchase(purchase, %{
         title: programme.title,
         version_number: version.number,
         weeks: version.weeks,
         days: if(Programmes.owned?(purchase), do: days, else: []),
         refund: quote(purchase, today, now),
         review: review && Presenter.review(review)
       })}
    end
  end

  defp quote(purchase, today, now) do
    case Programmes.refund_quote(purchase, today, now) do
      {:ok, quote} -> quote
      {:error, _reason} -> nil
    end
  end

  @doc """
  The buyer gives the programme up and gets what the rules give
  (`RefundRules.quote/3`): the refund goes through the seller's provider,
  the purchase ends and its future WODs go.
  """
  def withdraw(context, purchase_id) do
    now = DateTime.utc_now()
    today = today(context, now)

    with {:ok, purchase} <- own(context, purchase_id),
         {:ok, %{amount_cents: cents, rule: rule}} <-
           Programmes.refund_quote(purchase, today, now),
         {:ok, refund} <-
           Payments.refund(
             context,
             purchase.payment_intent_id,
             %{
               amount_cents: cents,
               reason: "Υπαναχώρηση / withdrawal (#{rule})",
               idempotency_key: "programme-withdrawal:" <> purchase.id
             },
             context.user_id,
             now
           ),
         {:ok, purchase} <-
           Programmes.step_purchase(context, purchase.id, {:refunded, cents, :withdrawal}, now),
         :ok <- Studio.remove_future(context, purchase, now) do
      :telemetry.execute([:palee, :programmes, :withdrawn], %{count: 1, amount_cents: cents}, %{
        organization_id: context.organization_id,
        id: purchase.id,
        rule: rule
      })

      {:ok, %{purchase: Presenter.purchase(purchase), refund: refund, rule: rule}}
    end
  end

  def review(context, purchase_id, params) do
    with {:ok, purchase} <- own(context, purchase_id),
         %{} = version <-
           Programmes.get_version(context, purchase.version_id) || {:error, :not_found},
         {:ok, review} <-
           Programmes.save_review(context, purchase, version.number, params, today(context)) do
      {:ok, Presenter.review(review)}
    end
  end

  @doc "Whether the buyer owns the programme a WOD belongs to (for opening it)."
  def workout_owned?(context, workout_id) do
    context
    |> Programmes.list_purchases(%{user_id: context.user_id, statuses: ~w(active completed)})
    |> Enum.any?(fn purchase ->
      case Programmes.get_version(context, purchase.version_id) do
        %{days: days} -> Enum.any?(days, &(&1["workout_id"] == workout_id))
        _none -> false
      end
    end)
  end

  # ── helpers ─────────────────────────────────────────────────────────────

  defp for_sale(context, id) do
    with %{} = programme <- Programmes.get_programme(context, id) || {:error, :not_found},
         true <- Programmes.on_sale?(programme) || {:error, :programme_not_for_sale},
         %{} = version <-
           Programmes.get_version(context, programme.current_version_id) || {:error, :not_found} do
      {:ok, programme, version}
    end
  end

  defp own(context, purchase_id) do
    case Programmes.get_purchase(context, purchase_id) do
      %{user_id: user_id} = purchase when user_id == context.user_id -> {:ok, purchase}
      _other -> {:error, :not_found}
    end
  end

  defp owned_purchase(context, programme_id) do
    case Programmes.open_purchase(context, programme_id, context.user_id) do
      nil -> nil
      purchase -> purchase.id
    end
  end

  defp today(context, now \\ DateTime.utc_now()),
    do: Organizations.local_today(context.organization_id, now)
end

defmodule Palee.Application.Programmes.Fulfilment do
  @moduledoc """
  ADR-371: what a succeeded `programme` payment does, called by
  `Payments.FinanceFulfilment` (retried until it succeeds, so every step
  is idempotent per intent):

    1. the buyer's membership in the seller's business (created on a first
       purchase, like a package bought online);
    2. the sale in Finance: an invoice line and an `online` payment of
       stream `other` with `source_type = programme_purchase` (revenue
       lineage, ADR-190/192), and its fiscal document (ADR-262);
    3. the purchase becomes active;
    4. the version's WODs are assigned to the buyer from the later of the
       start date and today (`programme_deliveries` keeps which).

  The purchase is the buyer's programming grant for these WODs only, like
  a season (ADR-167): it is not checked against the package
  (`AuthorizeProgramming`, ADR-225).

  A refund is a Finance reversal of the stream payment and a credit note.
  """

  require Logger

  alias Palee.Application.Fiscal.PaymentDocuments
  alias Palee.Application.GoLive
  alias Palee.{Finance, Organizations, Programmes, Workouts}

  @source "programme_purchase"

  def source_type, do: @source

  def fulfil(context, intent) do
    now = DateTime.utc_now()

    with %{} = purchase <- purchase(context, intent) || {:error, :programme_purchase_not_found},
         true <- intent.amount_cents == purchase.price_cents || {:error, :amount_mismatch},
         {:ok, membership} <- ensure_membership(context, purchase.user_id),
         {:ok, received} <- record_sale(context, intent, purchase, membership, now),
         {:ok, purchase} <- activate(context, purchase, received, now),
         :ok <- deliver(context, purchase, now) do
      {:ok,
       %{
         finance_payment_id: received.payment.id,
         fiscal_document_id: received[:fiscal_document] && received.fiscal_document.id
       }}
    end
  end

  defp purchase(context, intent) do
    Programmes.purchase_by_intent(context, intent.id) ||
      Programmes.get_purchase(context, intent.purpose_id)
  end

  defp ensure_membership(context, user_id) do
    case Finance.get_member_profile(context, user_id) do
      %{membership: %{} = membership} ->
        {:ok, membership}

      _none ->
        Finance.upsert_membership(context, user_id, %{
          user_type_snapshot: "member",
          status: "active",
          signup_source: "direct"
        })
    end
  end

  defp record_sale(context, intent, purchase, membership, now) do
    today = Organizations.local_today(context.organization_id, intent.succeeded_at || now)
    programme = Programmes.get_programme(context, purchase.programme_id)
    description = (programme && programme.title) || intent.description

    with :ok <- GoLive.check_payment(context, purchase.user_id),
         {:ok, recorded} <-
           Finance.record_stream_sale(
             context,
             sale(intent, purchase, membership, description, today)
           ) do
      received = %{
        payment: recorded.payment,
        invoice: recorded.invoice,
        description: description,
        amount_cents: recorded.payment.amount_cents,
        replayed: recorded.replayed
      }

      case PaymentDocuments.issue(context, received, nil, now) do
        {:ok, :not_configured} ->
          {:ok, Map.put(received, :fiscal_document, nil)}

        {:ok, document} ->
          {:ok, Map.put(received, :fiscal_document, PaymentDocuments.summary(document))}

        {:error, reason} ->
          {:error, {:fiscal_document_not_issued, reason}}
      end
    end
  end

  @doc "The Finance rows of one programme sale, for `Finance.record_stream_sale/2`."
  def sale(intent, purchase, membership, description, %Date{} = today) do
    params = %{
      "payment_intent_id" => intent.id,
      "provider" => intent.provider,
      "provider_transaction_id" => intent.provider_transaction_id,
      "purpose_type" => "programme",
      "programme_id" => purchase.programme_id,
      "programme_version_id" => purchase.version_id
    }

    %{
      "invoice" => %{
        "revenue_stream" => "other",
        "membership_id" => membership.id,
        "user_id" => purchase.user_id,
        "invoice_type" => "manual",
        "issue_date" => today,
        "due_date" => today,
        "currency" => purchase.currency,
        "notes" => description,
        "params" => params,
        "lines" => [
          %{
            "line_type" => "manual_charge",
            "charge_category" => "other",
            "revenue_stream" => "other",
            "source_type" => @source,
            "source_id" => purchase.id,
            "description" => description,
            "quantity" => 1,
            "unit_amount_cents" => purchase.price_cents,
            "discount_cents" => 0,
            "total_cents" => purchase.price_cents,
            "params" => params
          }
        ]
      },
      "payment" => %{
        "revenue_stream" => "other",
        "source_type" => @source,
        "source_id" => purchase.id,
        "membership_id" => membership.id,
        "amount_cents" => purchase.price_cents,
        "currency" => purchase.currency,
        "paid_on" => today,
        "payment_method" => "online",
        "payment_status" => "paid",
        "notes" => description,
        "params" => Map.put(params, "idempotency_key", "payment-intent:" <> intent.id)
      }
    }
  end

  defp activate(context, %{status: "pending_payment"} = purchase, received, now) do
    Programmes.step_purchase(
      context,
      purchase.id,
      {:paid,
       %{
         finance_payment_id: received.payment.id,
         fiscal_document_id: received[:fiscal_document] && received.fiscal_document.id
       }},
      now
    )
  end

  # Already active (a retried fulfilment): deliver again, idempotently.
  defp activate(_context, %{status: "active"} = purchase, _received, _now), do: {:ok, purchase}
  defp activate(_context, _purchase, _received, _now), do: {:error, :invalid_purchase_transition}

  @doc "Assigns the version's WODs to the buyer (idempotent: assignments merge, deliveries dedupe)."
  def deliver(context, purchase, now) do
    today = Organizations.local_today(context.organization_id, now)
    from = Enum.max([purchase.starts_on, today], Date)

    with %{} = version <-
           Programmes.get_version(context, purchase.version_id) || {:error, :not_found} do
      version.days
      |> Programmes.schedule(purchase.starts_on, from)
      |> Enum.reduce_while({:ok, []}, fn {date, day, workout_id}, {:ok, rows} ->
        case Workouts.assign_workout(context, %{
               master_workout_id: workout_id,
               scheduled_for: date,
               athlete_ids: [purchase.user_id]
             }) do
          {:ok, assignment} ->
            {:cont,
             {:ok, [%{assigned_workout_id: assignment.id, day: day, scheduled_for: date} | rows]}}

          {:error, reason} ->
            Logger.warning(
              "programme purchase #{purchase.id}: day #{day} not assigned: #{inspect(reason)}"
            )

            {:halt, {:error, :programme_workout_unavailable}}
        end
      end)
      |> case do
        {:ok, rows} -> Programmes.record_deliveries(context, purchase.id, purchase.user_id, rows)
        error -> error
      end
    end
  end

  @doc "Money given back for a programme payment: a Finance reversal and its credit note."
  def reverse(_context, %{finance_payment_id: nil}, _refund), do: {:ok, %{}}

  def reverse(context, intent, refund) do
    with {:ok, reversal} <-
           Finance.reverse_stream_payment(context, %{
             membership_payment_id: intent.finance_payment_id,
             amount_cents: refund.amount_cents,
             user_id: intent.user_id,
             reason: refund.reason || "programme refund",
             created_by_id: refund.created_by_id,
             idempotency_key: "payment-refund:" <> refund.id,
             params: %{"payment_intent_id" => intent.id, "payment_refund_id" => refund.id}
           }),
         {:ok, note} <-
           PaymentDocuments.credit(
             context,
             intent.finance_payment_id,
             %{
               id: reversal_id(reversal),
               amount_cents: refund.amount_cents,
               fiscal_credit: Map.get(refund, :fiscal_credit)
             },
             refund.created_by_id,
             DateTime.utc_now()
           ) do
      {:ok,
       %{
         finance_reversal_id: reversal_id(reversal),
         fiscal_document_id: if(is_map(note), do: note.id)
       }}
    end
  end

  defp reversal_id(%{reversal: %{id: id}}), do: id
  defp reversal_id(%{id: id}), do: id
  defp reversal_id(_other), do: nil
end

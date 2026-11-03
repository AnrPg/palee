defmodule Palee.Programmes do
  @moduledoc """
  The Programmes bounded context (ADR-370/371, CP-D4): multi-week training
  programmes a box or an independent coach builds from its own structured
  WODs and sells, to its own clients or in the cross-business catalogue.

  It owns the programme, its immutable published versions, each buyer's
  purchase (with the refund rule and withdrawal record copied at
  purchase), the WODs a purchase scheduled and the buyers' reviews. Money
  stays in Payments (the seller's own provider account) and Finance (the
  receipt or invoice, stream `other`, source `programme_purchase`); the WODs
  stay in Workouts. Use cases that need those live in
  `Palee.Application.Programmes.*`.

  Every function runs in the seller's scope (`organization_id`).
  """

  alias Palee.Programmes.Domain.{
    ProgrammePolicy,
    ProgrammeSchedule,
    PurchaseLifecycle,
    RefundRules,
    ReviewPolicy,
    TenantDataPolicy
  }

  alias Palee.Programmes.ProgrammeStore

  defdelegate create_programme(context, attrs), to: ProgrammeStore
  defdelegate update_programme(context, programme, attrs), to: ProgrammeStore
  defdelegate get_programme(context, id), to: ProgrammeStore
  defdelegate list_programmes(context, filters \\ %{}), to: ProgrammeStore
  defdelegate publish_version(context, programme_id, version_attrs, changes), to: ProgrammeStore
  defdelegate get_version(context, id), to: ProgrammeStore
  defdelegate list_versions(context, programme_id), to: ProgrammeStore
  defdelegate create_purchase(context, attrs), to: ProgrammeStore
  defdelegate get_purchase(context, id), to: ProgrammeStore
  defdelegate purchase_by_intent(context, intent_id), to: ProgrammeStore
  defdelegate open_purchase(context, programme_id, user_id), to: ProgrammeStore
  defdelegate set_purchase_intent(context, id, intent_id), to: ProgrammeStore
  defdelegate list_purchases(context, filters \\ %{}), to: ProgrammeStore
  defdelegate due_completions(context, today), to: ProgrammeStore
  defdelegate sales(context, programme_ids), to: ProgrammeStore
  defdelegate record_deliveries(context, purchase_id, user_id, rows), to: ProgrammeStore
  defdelegate deliveries(context, purchase_id, from \\ nil), to: ProgrammeStore
  defdelegate delete_deliveries(context, purchase_id, from), to: ProgrammeStore
  defdelegate get_review(context, id), to: ProgrammeStore
  defdelegate review_for_purchase(context, purchase_id), to: ProgrammeStore
  defdelegate list_reviews(context, programme_id, filters \\ %{}), to: ProgrammeStore
  defdelegate review_summaries(context, programme_ids), to: ProgrammeStore

  @doc "Moves a programme one lifecycle step (`:archive`, `:restore`)."
  def transition(context, programme, step, %DateTime{} = now) do
    with {:ok, changes} <- ProgrammePolicy.transition(programme, step, now) do
      ProgrammeStore.set_state(
        context,
        programme,
        Map.put(changes, :updated_by_id, Map.get(context, :user_id))
      )
    end
  end

  @doc "Applies a purchase lifecycle step under the row lock."
  def step_purchase(context, purchase_id, step, %DateTime{} = now) do
    ProgrammeStore.update_purchase(context, purchase_id, fn purchase ->
      PurchaseLifecycle.transition(purchase, step, now)
    end)
  end

  @doc "Writes a buyer's review of their purchase (`ReviewPolicy`)."
  def save_review(context, purchase, version_number, params, %Date{} = today) do
    with :ok <- ReviewPolicy.may_review(purchase, today),
         {:ok, fields} <- ReviewPolicy.normalize(params) do
      ProgrammeStore.save_review(
        context,
        purchase,
        Map.put(fields, :version_number, version_number)
      )
    end
  end

  @doc "Hides a review with a reason, or shows it again (`reason` nil)."
  def moderate_review(context, review, nil),
    do:
      ProgrammeStore.moderate_review(context, review, %{
        status: "published",
        hidden_reason: nil,
        hidden_by_id: nil
      })

  def moderate_review(context, review, reason) do
    with {:ok, reason} <- ReviewPolicy.hide_reason(reason) do
      ProgrammeStore.moderate_review(context, review, %{
        status: "hidden",
        hidden_reason: reason,
        hidden_by_id: Map.get(context, :user_id)
      })
    end
  end

  # ── Catalogue ───────────────────────────────────────────────────────────

  @doc "The cross-business catalogue (`Ports.Catalogue`)."
  def catalogue(filters), do: Application.fetch_env!(:palee, :programme_catalogue).search(filters)

  # ── Rules ───────────────────────────────────────────────────────────────

  defdelegate statuses(), to: ProgrammePolicy
  defdelegate listings(), to: ProgrammePolicy
  defdelegate levels(), to: ProgrammePolicy
  defdelegate goals(), to: ProgrammePolicy
  defdelegate refund_policies(), to: ProgrammePolicy
  defdelegate normalize_days(days, weeks), to: ProgrammePolicy
  defdelegate workout_ids(days), to: ProgrammePolicy
  defdelegate publishable(programme, days), to: ProgrammePolicy
  defdelegate on_sale?(programme), to: ProgrammePolicy
  defdelegate in_marketplace?(programme), to: ProgrammePolicy
  defdelegate preview(days, preview_days), to: ProgrammePolicy
  defdelegate purchase_statuses(), to: PurchaseLifecycle, as: :statuses
  defdelegate owned?(purchase), to: PurchaseLifecycle
  defdelegate delivering?(purchase), to: PurchaseLifecycle
  defdelegate check_start(starts_on, today), to: RefundRules
  defdelegate ends_on(starts_on, weeks), to: RefundRules
  defdelegate refund_quote(purchase, today, now), to: RefundRules, as: :quote
  defdelegate check_staff_refund(purchase, amount_cents), to: RefundRules, as: :check_staff_amount
  defdelegate schedule(days, starts_on, from), to: ProgrammeSchedule, as: :dates
  defdelegate hide_reasons(), to: ReviewPolicy

  # Tenant data lifecycle (ADR-117).
  def tenant_data_policy, do: TenantDataPolicy.policy()

  def tenant_data_inventory(context),
    do: Palee.TenantData.TableStore.inventory(tenant_data_policy(), context)

  def export_tenant_data(context, mode \\ :full),
    do: Palee.TenantData.TableStore.export(tenant_data_policy(), context, mode)

  def purge_tenant_data(context),
    do: Palee.TenantData.TableStore.purge(tenant_data_policy(), context)
end

defmodule Palee.Programmes.ProgrammeStore do
  @moduledoc "Facade over the programmes adapter (ADR-370/371); every call runs in the caller's session."

  @behaviour Palee.Programmes.Ports.ProgrammeStore

  alias Palee.Infrastructure.Tenancy.RepoContext

  defp adapter, do: Application.fetch_env!(:palee, :programme_store)

  defp call(context, function, args),
    do: RepoContext.run(context, fn -> apply(adapter(), function, [context | args]) end)

  @impl true
  def create_programme(context, attrs), do: call(context, :create_programme, [attrs])
  @impl true
  def update_programme(context, programme, attrs),
    do: call(context, :update_programme, [programme, attrs])

  @impl true
  def set_state(context, programme, changes), do: call(context, :set_state, [programme, changes])
  @impl true
  def get_programme(context, id), do: call(context, :get_programme, [id])
  @impl true
  def list_programmes(context, filters), do: call(context, :list_programmes, [filters])

  @impl true
  def publish_version(context, programme_id, version_attrs, programme_changes),
    do: call(context, :publish_version, [programme_id, version_attrs, programme_changes])

  @impl true
  def get_version(context, id), do: call(context, :get_version, [id])
  @impl true
  def list_versions(context, programme_id), do: call(context, :list_versions, [programme_id])
  @impl true
  def create_purchase(context, attrs), do: call(context, :create_purchase, [attrs])
  @impl true
  def get_purchase(context, id), do: call(context, :get_purchase, [id])
  @impl true
  def purchase_by_intent(context, intent_id), do: call(context, :purchase_by_intent, [intent_id])
  @impl true
  def open_purchase(context, programme_id, user_id),
    do: call(context, :open_purchase, [programme_id, user_id])

  @impl true
  def set_purchase_intent(context, id, intent_id),
    do: call(context, :set_purchase_intent, [id, intent_id])

  @impl true
  def update_purchase(context, id, decide), do: call(context, :update_purchase, [id, decide])
  @impl true
  def list_purchases(context, filters), do: call(context, :list_purchases, [filters])
  @impl true
  def due_completions(context, today), do: call(context, :due_completions, [today])
  @impl true
  def sales(context, programme_ids), do: call(context, :sales, [programme_ids])

  @impl true
  def record_deliveries(context, purchase_id, user_id, rows),
    do: call(context, :record_deliveries, [purchase_id, user_id, rows])

  @impl true
  def deliveries(context, purchase_id, from), do: call(context, :deliveries, [purchase_id, from])
  @impl true
  def delete_deliveries(context, purchase_id, from),
    do: call(context, :delete_deliveries, [purchase_id, from])

  @impl true
  def save_review(context, purchase, attrs), do: call(context, :save_review, [purchase, attrs])
  @impl true
  def get_review(context, id), do: call(context, :get_review, [id])
  @impl true
  def review_for_purchase(context, purchase_id),
    do: call(context, :review_for_purchase, [purchase_id])

  @impl true
  def list_reviews(context, programme_id, filters),
    do: call(context, :list_reviews, [programme_id, filters])

  @impl true
  def moderate_review(context, review, changes),
    do: call(context, :moderate_review, [review, changes])

  @impl true
  def review_summaries(context, programme_ids),
    do: call(context, :review_summaries, [programme_ids])
end

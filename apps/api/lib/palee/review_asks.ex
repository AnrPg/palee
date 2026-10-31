defmodule Palee.ReviewAsks do
  @moduledoc """
  The ReviewAsks bounded context (ADR-355): asking members for a Google
  review at a good moment, the same way for everyone, never gated by their
  opinion and never rewarded, with an opt-out.
  """

  alias Palee.ReviewAsks.Domain.{ReviewAskPolicy, TenantDataPolicy}
  alias Palee.ReviewAsks.ReviewAskStore

  @doc "The configured clock (`ReviewAsks.Ports.Clock`)."
  def clock, do: Application.fetch_env!(:palee, :review_ask_clock)
  @doc "The configured signals (`ReviewAsks.Ports.ReviewSignals`)."
  def signals, do: Application.fetch_env!(:palee, :review_signals)

  @doc "The box's settings, or the defaults (asks off)."
  def settings(context),
    do: ReviewAskStore.get_settings(context) || ReviewAskPolicy.default_settings()

  @doc "Saves an edit (string keys) against its `lock_version`."
  def update_settings(context, params, user_id) do
    current = settings(context)

    with {:ok, changes} <- ReviewAskPolicy.changes(current, params) do
      lock = Map.get(params, "lock_version", current.lock_version)

      case ReviewAskStore.save_settings(context, Map.put(changes, :updated_by_id, user_id), lock) do
        {:error, :stale} -> {:error, :settings_changed_meanwhile}
        result -> result
      end
    end
  end

  defdelegate list_asks(context, user_id), to: ReviewAskStore
  defdelegate get_ask(context, id, user_id), to: ReviewAskStore
  defdelegate opted_out?(context, user_id), to: ReviewAskStore
  defdelegate opt_out(context, user_id, now), to: ReviewAskStore
  defdelegate opt_in(context, user_id), to: ReviewAskStore
  defdelegate summary(context, since), to: ReviewAskStore
  defdelegate decide(settings, facts, asks, opted_out?, local_hour, now), to: ReviewAskPolicy
  defdelegate open_ask(asks, now), to: ReviewAskPolicy
  defdelegate write_review_url(place_id), to: ReviewAskPolicy
  defdelegate read_reviews_url(place_id), to: ReviewAskPolicy
  defdelegate actions(), to: ReviewAskPolicy

  @doc "Records an ask shown to a member now."
  def record_ask(context, user_id, milestone, now) do
    ReviewAskStore.insert_ask(context, %{
      user_id: user_id,
      trigger: "attendance_milestone",
      milestone: milestone,
      status: "shown",
      shown_at: now
    })
  end

  @doc "Records a member's answer to their own ask."
  def respond(context, user_id, id, action, now) do
    with %{} = ask <-
           ReviewAskStore.get_ask(context, id, user_id) || {:error, :review_ask_not_found},
         {:ok, changes} <- ReviewAskPolicy.respond(ask, action, now) do
      if changes == %{}, do: {:ok, ask}, else: ReviewAskStore.update_ask(context, ask.id, changes)
    end
  end

  def tenant_data_policy, do: TenantDataPolicy.policy()

  def tenant_data_inventory(context),
    do: Palee.TenantData.TableStore.inventory(tenant_data_policy(), context)

  def export_tenant_data(context, mode \\ :full),
    do: Palee.TenantData.TableStore.export(tenant_data_policy(), context, mode)

  def purge_tenant_data(context),
    do: Palee.TenantData.TableStore.purge(tenant_data_policy(), context)
end

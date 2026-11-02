defmodule Palee.ReviewAsks.ReviewAskStore do
  @moduledoc "Facade over the review ask adapter (ADR-355); every call runs in the caller's session."

  @behaviour Palee.ReviewAsks.Ports.ReviewAskStore

  alias Palee.Infrastructure.Tenancy.RepoContext

  defp adapter, do: Application.fetch_env!(:palee, :review_ask_store)

  defp call(context, function, args),
    do: RepoContext.run(context, fn -> apply(adapter(), function, [context | args]) end)

  @impl true
  def get_settings(context), do: call(context, :get_settings, [])
  @impl true
  def save_settings(context, changes, lock), do: call(context, :save_settings, [changes, lock])
  @impl true
  def list_asks(context, user_id), do: call(context, :list_asks, [user_id])
  @impl true
  def insert_ask(context, attrs), do: call(context, :insert_ask, [attrs])
  @impl true
  def get_ask(context, id, user_id), do: call(context, :get_ask, [id, user_id])
  @impl true
  def update_ask(context, id, changes), do: call(context, :update_ask, [id, changes])
  @impl true
  def opted_out?(context, user_id), do: call(context, :opted_out?, [user_id])
  @impl true
  def opt_out(context, user_id, now), do: call(context, :opt_out, [user_id, now])
  @impl true
  def opt_in(context, user_id), do: call(context, :opt_in, [user_id])
  @impl true
  def summary(context, since), do: call(context, :summary, [since])
  @impl true
  def get_review(context, user_id), do: call(context, :get_review, [user_id])
  @impl true
  def get_review_by_id(context, id), do: call(context, :get_review_by_id, [id])
  @impl true
  def save_review(context, user_id, attrs), do: call(context, :save_review, [user_id, attrs])
  @impl true
  def delete_review(context, user_id), do: call(context, :delete_review, [user_id])
  @impl true
  def list_reviews(context, page), do: call(context, :list_reviews, [page])
  @impl true
  def review_stats(context), do: call(context, :review_stats, [])
  @impl true
  def reply_review(context, id, attrs), do: call(context, :reply_review, [id, attrs])
  @impl true
  def get_place_snapshot(context), do: call(context, :get_place_snapshot, [])
  @impl true
  def save_place_snapshot(context, attrs), do: call(context, :save_place_snapshot, [attrs])
  @impl true
  def place_due_organizations(now), do: adapter().place_due_organizations(now)
end

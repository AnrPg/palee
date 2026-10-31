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
end

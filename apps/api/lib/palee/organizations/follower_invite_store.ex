defmodule Palee.Organizations.FollowerInviteStore do
  @moduledoc "ADR-580: dispatches to the configured `Palee.Organizations.Ports.FollowerInviteStore`."

  @behaviour Palee.Organizations.Ports.FollowerInviteStore

  alias Palee.Infrastructure.Tenancy.RepoContext

  defp adapter, do: Application.fetch_env!(:palee, :follower_invite_store)

  @doc "Runs `fun` inside the scope of `context` (`organization_id`, `user_id`)."
  def with_scope(context, fun) when is_function(fun, 0), do: RepoContext.run(context, fun)

  @impl true
  def list_followers(filter, limit, before, now),
    do: adapter().list_followers(filter, limit, before, now)

  @impl true
  def counts(now), do: adapter().counts(now)
  @impl true
  def followers_among(user_ids, now), do: adapter().followers_among(user_ids, now)
  @impl true
  def create_many(user_ids, content, now), do: adapter().create_many(user_ids, content, now)
  @impl true
  def latest_for(user_id), do: adapter().latest_for(user_id)
  @impl true
  def decline(user_id, now), do: adapter().decline(user_id, now)
end

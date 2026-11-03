defmodule Palee.Ranks.RankStore do
  @moduledoc "Dispatches the ranks persistence port to the configured adapter (ADR-377)."

  @behaviour Palee.Ranks.Ports.RankStore

  alias Palee.Infrastructure.Tenancy.RepoContext

  def with_context(context, fun) when is_function(fun, 0), do: RepoContext.run(context, fun)

  @impl true
  def list_ladders, do: adapter().list_ladders()
  @impl true
  def get_ladder(id), do: adapter().get_ladder(id)
  @impl true
  def insert_ladder(attrs, ranks), do: adapter().insert_ladder(attrs, ranks)
  @impl true
  def update_ladder(ladder, attrs, ranks), do: adapter().update_ladder(ladder, attrs, ranks)
  @impl true
  def archive_ladder(ladder, now), do: adapter().archive_ladder(ladder, now)

  @impl true
  def list_awards(user_id), do: adapter().list_awards(user_id)
  @impl true
  def get_award(id), do: adapter().get_award(id)
  @impl true
  def insert_award(attrs), do: adapter().insert_award(attrs)
  @impl true
  def revoke_award(award, attrs), do: adapter().revoke_award(award, attrs)

  @impl true
  def list_skill_checks(user_id), do: adapter().list_skill_checks(user_id)
  @impl true
  def put_skill_check(attrs), do: adapter().put_skill_check(attrs)
  @impl true
  def delete_skill_check(user_id, rank_id, skill),
    do: adapter().delete_skill_check(user_id, rank_id, skill)

  defp adapter, do: Application.fetch_env!(:palee, :rank_store)
end

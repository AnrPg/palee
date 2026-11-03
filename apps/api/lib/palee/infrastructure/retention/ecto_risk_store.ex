defmodule Palee.Infrastructure.Retention.EctoRiskStore do
  @moduledoc "ADR-347: box members' latest risk scores in Postgres (forced RLS per box)."

  @behaviour Palee.Retention.Ports.RiskStore

  import Ecto.Query

  alias Palee.Repo
  alias Palee.Retention.{Risk, RiskAction}

  @impl true
  def all(context), do: context |> scoped() |> Repo.all() |> Map.new(&{&1.user_id, &1})

  @impl true
  def get(context, user_id) do
    case Ecto.UUID.cast(user_id) do
      {:ok, id} -> context |> scoped() |> where([r], r.user_id == ^id) |> Repo.one()
      :error -> nil
    end
  end

  @impl true
  def put(context, user_id, attrs) do
    (get(context, user_id) || %Risk{user_id: user_id})
    |> Risk.changeset(Map.put(attrs, :user_id, user_id))
    |> Repo.insert_or_update()
  end

  @impl true
  def delete_except(context, user_ids) do
    # ADR-384: a former box member's action log goes with their risk.
    context
    |> scoped_actions()
    |> where([a], a.user_id not in ^user_ids)
    |> Repo.delete_all()

    {count, _rows} =
      context |> scoped() |> where([r], r.user_id not in ^user_ids) |> Repo.delete_all()

    count
  end

  @impl true
  def list(context, filters) do
    limit = filters |> Map.get(:limit, 100) |> min(200) |> max(1)
    today = Map.fetch!(filters, :today)

    context
    |> scoped()
    |> where([r], r.level in ^filters.levels)
    |> then(fn query ->
      if Map.get(filters, :include_snoozed, false),
        do: query,
        else: where(query, [r], is_nil(r.snoozed_until) or r.snoozed_until < ^today)
    end)
    |> order_by([r], desc: r.score, asc: r.user_id)
    |> limit(^limit)
    |> Repo.all()
  end

  @impl true
  def level_counts(context) do
    context
    |> scoped()
    |> group_by([r], r.level)
    |> select([r], {r.level, count(r.id)})
    |> Repo.all()
    |> Map.new()
  end

  @impl true
  def add_action(_context, user_id, attrs) do
    %RiskAction{}
    |> RiskAction.changeset(Map.put(attrs, :user_id, user_id))
    |> Repo.insert()
  end

  @impl true
  def actions(context, user_id, limit) do
    case Ecto.UUID.cast(user_id) do
      {:ok, id} ->
        context
        |> scoped_actions()
        |> where([a], a.user_id == ^id)
        |> order_by([a], desc: a.at, desc: a.id)
        |> limit(^(limit |> min(100) |> max(1)))
        |> Repo.all()

      :error ->
        []
    end
  end

  defp scoped_actions(%{organization_id: organization_id}) when is_binary(organization_id),
    do: from(a in RiskAction, where: a.organization_id == ^organization_id)

  defp scoped_actions(_context), do: from(a in RiskAction, where: false)

  defp scoped(%{organization_id: organization_id}) when is_binary(organization_id),
    do: from(r in Risk, where: r.organization_id == ^organization_id)

  defp scoped(_context), do: from(r in Risk, where: false)
end

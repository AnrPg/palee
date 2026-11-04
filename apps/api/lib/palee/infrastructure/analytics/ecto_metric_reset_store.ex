defmodule Palee.Infrastructure.Analytics.EctoMetricResetStore do
  @moduledoc """
  ADR-462 metric baselines in `analytics_metric_resets`. Runs in the scope
  the facade opened: a box's rows under its tenant policy, a member's own
  under the owner policy, so neither can see the other's.
  """

  @behaviour Palee.Analytics.Ports.MetricResetStore

  import Ecto.Query

  alias Palee.Analytics.MetricReset
  alias Palee.Infrastructure.Tenancy.RepoContext
  alias Palee.Repo

  @impl true
  def insert_reset(scope, attrs) do
    attrs =
      attrs
      |> Map.put(:scope, to_string(scope))
      |> put_owner(scope)

    %MetricReset{}
    |> MetricReset.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, reset} -> {:ok, normalize(reset)}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @impl true
  def undo_reset(scope, id, actor_id, %DateTime{} = now) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %MetricReset{} = reset <- scope |> scoped() |> where([r], r.id == ^id) |> Repo.one() do
      if reset.undone_at do
        {:error, :already_undone}
      else
        reset
        |> Ecto.Changeset.change(undone_at: now, undone_by: actor_id)
        |> Repo.update()
        |> case do
          {:ok, reset} -> {:ok, normalize(reset)}
          {:error, changeset} -> {:error, changeset}
        end
      end
    else
      _missing -> {:error, :not_found}
    end
  end

  @impl true
  def list_resets(scope, opts) do
    limit = Keyword.get(opts, :limit, 20)
    offset = Keyword.get(opts, :offset, 0)
    query = scope |> scoped() |> for_metric(Keyword.get(opts, :metric_key))

    %{
      entries:
        query
        |> order_by([r], desc: r.reset_at, desc: r.id)
        |> limit(^limit)
        |> offset(^offset)
        |> Repo.all()
        |> Enum.map(&normalize/1),
      total: Repo.aggregate(query, :count)
    }
  end

  @impl true
  def active_resets(scope) do
    scope
    |> scoped()
    |> where([r], is_nil(r.undone_at))
    |> Repo.all()
    |> Enum.map(&normalize/1)
  end

  defp for_metric(query, nil), do: query
  defp for_metric(query, key), do: where(query, [r], r.metric_key == ^key)

  defp scoped(:organization) do
    organization_id = RepoContext.current_setting("app.organization_id")

    from(r in MetricReset,
      where: r.scope == "organization" and r.organization_id == ^organization_id
    )
  end

  defp scoped(:member) do
    user_id = RepoContext.current_setting("app.user_id")
    from(r in MetricReset, where: r.scope == "member" and r.user_id == ^user_id)
  end

  defp put_owner(attrs, :organization),
    do:
      attrs
      |> Map.put(:organization_id, RepoContext.current_setting("app.organization_id"))
      |> Map.put(:user_id, nil)

  defp put_owner(attrs, :member),
    do:
      attrs
      |> Map.put(:user_id, RepoContext.current_setting("app.user_id"))
      |> Map.put(:organization_id, nil)

  defp normalize(%MetricReset{} = reset) do
    %{
      id: reset.id,
      scope: reset.scope,
      organization_id: reset.organization_id,
      user_id: reset.user_id,
      metric_key: reset.metric_key,
      reset_at: reset.reset_at,
      reset_by: reset.reset_by,
      undone_at: reset.undone_at,
      undone_by: reset.undone_by
    }
  end
end

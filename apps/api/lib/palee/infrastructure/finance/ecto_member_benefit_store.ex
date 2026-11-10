defmodule Palee.Infrastructure.Finance.EctoMemberBenefitStore do
  @moduledoc """
  ADR-612: the member benefits ledger in Postgres (RLS by tenant). Rows are
  only inserted; the table's trigger refuses an update.
  """

  @behaviour Palee.Finance.Ports.MemberBenefitStore

  import Ecto.Query

  alias Palee.Finance.Domain.MemberBenefits
  alias Palee.Finance.MemberBenefit
  alias Palee.Infrastructure.Tenancy.RepoContext
  alias Palee.Repo

  @impl true
  def insert(params) do
    params
    |> MemberBenefit.changeset()
    |> Repo.insert()
    |> case do
      {:ok, row} -> {:ok, normalize(row)}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @impl true
  def by_idempotency_key(key) when is_binary(key) do
    MemberBenefit
    |> tenant_scope()
    |> where([b], b.idempotency_key == ^key)
    |> Repo.one()
    |> normalize()
  end

  @impl true
  def lock_grant(membership_id, id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} ->
        MemberBenefit
        |> tenant_scope()
        |> where([b], b.id == ^id and b.membership_id == ^membership_id and b.action == "grant")
        |> lock("FOR UPDATE")
        |> Repo.one()
        |> normalize()

      :error ->
        nil
    end
  end

  @impl true
  def list(membership_id) do
    MemberBenefit
    |> tenant_scope()
    |> where([b], b.membership_id == ^membership_id)
    |> order_by([b], desc: b.inserted_at, desc: b.id)
    |> Repo.all()
    |> Enum.map(&normalize/1)
  end

  @impl true
  def access(membership_id, %Date{} = today) do
    kinds = MemberBenefits.access_kinds()

    grants =
      from(b in MemberBenefit, as: :grant)
      |> tenant_scope()
      |> where([b], b.membership_id == ^membership_id and b.action == "grant")
      |> where([b], b.kind in ^kinds and b.starts_on <= ^today and b.ends_on >= ^today)
      |> where(
        [b],
        not exists(
          from(r in MemberBenefit,
            where: r.benefit_id == parent_as(:grant).id and r.action == "revoke",
            select: 1
          )
        )
      )
      |> select([b], %{id: b.id, kind: b.kind, starts_on: b.starts_on, ends_on: b.ends_on})
      |> Repo.all()

    MemberBenefits.access(grants, [], today)
  end

  @impl true
  def transaction(fun) when is_function(fun, 0) do
    Repo.transaction(fn ->
      case fun.() do
        {:ok, value} -> value
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp normalize(nil), do: nil

  defp normalize(%MemberBenefit{} = row) do
    %{
      id: row.id,
      membership_id: row.membership_id,
      user_id: row.user_id,
      action: row.action,
      kind: row.kind,
      benefit_id: row.benefit_id,
      starts_on: row.starts_on,
      ends_on: row.ends_on,
      amount_cents: row.amount_cents,
      details: row.details || %{},
      reason: row.reason,
      actor_id: row.actor_id,
      actor_roles: row.actor_roles || [],
      request_id: row.request_id,
      idempotency_key: row.idempotency_key,
      inserted_at: row.inserted_at
    }
  end

  defp tenant_scope(queryable) do
    case RepoContext.current_setting("app.organization_id") do
      organization_id when is_binary(organization_id) and organization_id != "" ->
        from(row in queryable, where: field(row, :organization_id) == ^organization_id)

      _none ->
        from(row in queryable, where: false)
    end
  end
end

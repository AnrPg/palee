defmodule Palee.Infrastructure.Finance.EctoPackageAudienceStore do
  @moduledoc "ADR-553: who sees the subscription packages, in Postgres (RLS by tenant)."

  @behaviour Palee.Finance.Ports.PackageAudienceStore

  import Ecto.Query

  alias Palee.Finance.{
    FinanceSetting,
    Membership,
    MembershipPackage,
    MembershipPackageSubscription,
    PackageAudienceException
  }

  alias Palee.Infrastructure.Tenancy.RepoContext
  alias Palee.Repo

  @impl true
  def load do
    {box, featured} =
      FinanceSetting
      |> tenant_scope()
      |> select([s], {s.package_audience, s.featured_package_id})
      |> limit(1)
      |> Repo.one() || {nil, nil}

    packages =
      MembershipPackage
      |> tenant_scope()
      |> where([p], not is_nil(p.audience))
      |> select([p], {p.id, p.audience})
      |> Repo.all()
      |> Map.new()

    exceptions =
      PackageAudienceException
      |> tenant_scope()
      |> order_by([e], asc: e.inserted_at)
      |> Repo.all()
      |> Enum.map(&normalize/1)

    %{box: box || "all", packages: packages, exceptions: exceptions, featured: featured}
  end

  @impl true
  def set_box(audience) do
    case put_settings(%{package_audience: audience}) do
      {:ok, settings} -> {:ok, settings.package_audience}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @impl true
  def set_featured(nil), do: featured(nil)

  def set_featured(id) do
    if package(id), do: featured(id), else: {:error, :not_found}
  end

  defp featured(id) do
    case put_settings(%{featured_package_id: id}) do
      {:ok, settings} -> {:ok, settings.featured_package_id}
      {:error, changeset} -> {:error, changeset}
    end
  end

  # The box's one finance settings row, created on the first change.
  defp put_settings(changes) do
    case FinanceSetting |> tenant_scope() |> limit(1) |> Repo.one() do
      nil ->
        %FinanceSetting{}
        |> FinanceSetting.changeset(changes)
        |> Repo.insert()

      %FinanceSetting{} = settings ->
        settings |> FinanceSetting.changeset(changes) |> Repo.update()
    end
  end

  @impl true
  def set_package(id, audience) do
    case MembershipPackage |> tenant_scope() |> where([p], p.id == ^id) |> Repo.one() do
      nil ->
        {:error, :not_found}

      package ->
        package
        |> MembershipPackage.audience_changeset(%{audience: audience})
        |> Repo.update()
        |> case do
          {:ok, updated} -> {:ok, %{id: updated.id, audience: updated.audience}}
          {:error, changeset} -> {:error, changeset}
        end
    end
  end

  @impl true
  def put_exception(params) do
    package_id = params[:package_id]

    Repo.transaction(fn ->
      if package_id && is_nil(package(package_id)), do: Repo.rollback(:not_found)

      existing =
        PackageAudienceException
        |> tenant_scope()
        |> where([e], e.user_id == ^params.user_id)
        |> same_package(package_id)
        |> lock("FOR UPDATE")
        |> Repo.one()

      (existing || %PackageAudienceException{})
      |> PackageAudienceException.changeset(%{
        membership_package_id: package_id,
        user_id: params.user_id,
        effect: params.effect,
        created_by_id: params[:created_by_id]
      })
      |> Repo.insert_or_update()
      |> case do
        {:ok, exception} -> normalize(exception)
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  defp same_package(query, nil), do: where(query, [e], is_nil(e.membership_package_id))
  defp same_package(query, id), do: where(query, [e], e.membership_package_id == ^id)

  defp package(id),
    do: MembershipPackage |> tenant_scope() |> where([p], p.id == ^id) |> Repo.one()

  @impl true
  def delete_exception(id) do
    case PackageAudienceException
         |> tenant_scope()
         |> where([e], e.id == ^id)
         |> Repo.delete_all() do
      {0, _rows} -> {:error, :not_found}
      {_count, _rows} -> :ok
    end
  end

  @impl true
  def holdings(user_id) do
    memberships =
      Membership
      |> tenant_scope()
      |> where([m], m.user_id == ^user_id)
      |> select([m], %{id: m.id, left_at: m.left_at})
      |> Repo.all()

    ids = Enum.map(memberships, & &1.id)

    subscriptions =
      MembershipPackageSubscription
      |> tenant_scope()
      |> where([s], s.membership_id in ^ids)
      |> select([s], %{
        membership_package_id: s.membership_package_id,
        status: s.status,
        starts_on: s.starts_on,
        inserted_at: s.inserted_at
      })
      |> Repo.all()

    %{subscriptions: subscriptions, member?: Enum.any?(memberships, &is_nil(&1.left_at))}
  end

  defp normalize(%PackageAudienceException{} = exception) do
    %{
      id: exception.id,
      package_id: exception.membership_package_id,
      user_id: exception.user_id,
      effect: exception.effect,
      inserted_at: exception.inserted_at
    }
  end

  defp organization_id, do: RepoContext.current_setting("app.organization_id")

  defp tenant_scope(queryable) do
    case organization_id() do
      organization_id when is_binary(organization_id) and organization_id != "" ->
        from(row in queryable, where: field(row, :organization_id) == ^organization_id)

      _none ->
        from(row in queryable, where: false)
    end
  end
end

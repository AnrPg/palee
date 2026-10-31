defmodule Palee.Infrastructure.BoxData.EctoExportStore do
  @moduledoc "Ecto adapter of `Palee.BoxData.Ports.ExportStore` (ADR-365)."

  @behaviour Palee.BoxData.Ports.ExportStore

  import Ecto.Query

  alias Palee.BoxData.Export
  alias Palee.Repo

  @impl true
  def list(organization_id) do
    Export
    |> where([e], e.organization_id == ^organization_id)
    |> order_by([e], desc: e.requested_at, desc: e.id)
    |> limit(20)
    |> Repo.all()
  end

  @impl true
  def get(id, organization_id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} ->
        Export |> where([e], e.id == ^id and e.organization_id == ^organization_id) |> Repo.one()

      :error ->
        nil
    end
  end

  @impl true
  def insert(attrs), do: attrs |> Export.create_changeset() |> Repo.insert()

  @impl true
  def finish(%Export{id: id, organization_id: organization_id}, attrs) do
    Repo.transaction(fn ->
      case Export
           |> where([e], e.id == ^id and e.organization_id == ^organization_id)
           |> lock("FOR UPDATE")
           |> Repo.one() do
        %Export{status: "pending"} = export ->
          case export |> Export.finish_changeset(attrs) |> Repo.update() do
            {:ok, finished} -> finished
            {:error, changeset} -> Repo.rollback(changeset)
          end

        _other ->
          Repo.rollback(:not_pending)
      end
    end)
  end
end

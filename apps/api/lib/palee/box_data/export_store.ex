defmodule Palee.BoxData.ExportStore do
  @moduledoc """
  Facade over the configured box data export store (ADR-365). Every call
  runs in a `RepoContext` session scoped to the box.
  """

  @behaviour Palee.BoxData.Ports.ExportStore

  alias Palee.Infrastructure.Tenancy.RepoContext

  @impl true
  def list(organization_id),
    do: tenant(organization_id, fn -> adapter().list(organization_id) end)

  @impl true
  def get(id, organization_id),
    do: tenant(organization_id, fn -> adapter().get(id, organization_id) end)

  @impl true
  def insert(%{organization_id: organization_id} = attrs),
    do: tenant(organization_id, fn -> adapter().insert(attrs) end)

  @impl true
  def finish(%{organization_id: organization_id} = export, attrs),
    do: tenant(organization_id, fn -> adapter().finish(export, attrs) end)

  defp tenant(organization_id, fun) when is_binary(organization_id),
    do: RepoContext.run(%{organization_id: organization_id}, fun)

  defp adapter do
    Application.get_env(
      :palee,
      :box_data_export_store,
      Palee.Infrastructure.BoxData.EctoExportStore
    )
  end
end

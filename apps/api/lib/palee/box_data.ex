defmodule Palee.BoxData do
  @moduledoc """
  The box's own copy of its data (ADR-365, CP-G5): «what happens if Palee
  closes, or we leave?». An owner asks for it at any time and gets one ZIP of
  CSV files with every table of the box that the owner may read, built from
  each bounded context's own export (the ADR-117 policies), plus (ADR-367)
  the box's stored files (photos, PDFs) in ZIP parts.
  """

  alias Palee.BoxData.Domain.{CsvBundle, ExportPolicy, FilePacking, TenantDataPolicy}
  alias Palee.BoxData.ExportStore
  alias Palee.TenantData.{BoxExportContext, TableStore}

  ## Tenant data (ADR-117)

  def tenant_data_policy, do: TenantDataPolicy.policy()
  def tenant_data_inventory(context), do: TableStore.inventory(tenant_data_policy(), context)

  def export_tenant_data(context, mode \\ :full),
    do: TableStore.export(tenant_data_policy(), context, mode)

  def purge_tenant_data(context), do: TableStore.purge(tenant_data_policy(), context)

  ## Exports

  def list_exports(organization_id), do: ExportStore.list(organization_id)
  def get_export(id, organization_id), do: ExportStore.get(id, organization_id)

  def request_export(organization_id, user_id, %DateTime{} = now) do
    with :ok <- ExportPolicy.can_request?(ExportStore.list(organization_id), now) do
      case ExportStore.insert(%{
             organization_id: organization_id,
             requested_by_id: user_id,
             requested_at: now
           }) do
        {:ok, export} ->
          {:ok, export}

        {:error, %Ecto.Changeset{errors: errors} = changeset} ->
          if Keyword.has_key?(errors, :organization_id),
            do: {:error, :export_in_progress},
            else: {:error, changeset}
      end
    end
  end

  def finish_export(export, attrs), do: ExportStore.finish(export, attrs)

  @doc "The scope a pending export reads the box's tables in (the owner who asked)."
  def export_context(%{status: "pending", id: id, organization_id: organization_id}, user_id)
      when is_binary(user_id),
      do:
        {:ok,
         %BoxExportContext{organization_id: organization_id, export_id: id, user_id: user_id}}

  def export_context(_export, _user_id), do: {:error, :box_export_not_found}

  def build_bundle(organization, sections, %DateTime{} = now),
    do: CsvBundle.build(%{organization: organization, sections: sections, generated_at: now})

  defdelegate expires_at(now), to: ExportPolicy
  defdelegate visible_status(export, now), to: ExportPolicy
  defdelegate downloadable?(export, now), to: ExportPolicy
  defdelegate file_name(slug, now), to: ExportPolicy
  defdelegate object_folder(export_id), to: ExportPolicy
  defdelegate keep_days, to: ExportPolicy
  defdelegate part_name(slug, now, index), to: ExportPolicy

  ## Stored files (ADR-367)

  defdelegate select_files(objects, tenant_prefix), to: FilePacking, as: :select
  defdelegate plan_parts(objects, max_bytes), to: FilePacking, as: :plan
end

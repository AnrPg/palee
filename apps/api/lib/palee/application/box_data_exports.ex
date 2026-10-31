defmodule Palee.Application.BoxDataExports do
  @moduledoc """
  ADR-365 (CP-G5): «Λήψη των δεδομένων του box» / "Download the box's data",
  for owners (`manage_organization_lifecycle`).

  1. `request/1` (`POST /api/org/:slug/admin/data-exports`) records a
     request (one in progress, one a day) and queues `BoxDataExportJob`.
  2. The job (`build/2`) reads every bounded context's tables through its
     public `export_tenant_data/2` in the owner's own tenant session (RLS
     applies: the owner gets what the owner may read; members' personal
     tables and secret columns are left out), writes one ZIP of CSV files
     under the box's storage prefix, and marks the request ready.
  3. `list/1` (`GET .../data-exports`) shows the requests; a ready file gets
     a short-lived signed download link, made afresh on every call, until
     it expires after `keep_days` days. Files of expired requests are
     deleted when the next one is asked for.
  """

  require Logger

  alias Palee.{BoxData, Organizations}
  alias Palee.Application.{TenantDataContexts, TenantObjectStorage}
  alias Palee.Workers.BoxDataExportJob

  @capability :manage_organization_lifecycle

  def request(context, now \\ DateTime.utc_now()) do
    with :ok <- Organizations.authorize_capability(context, @capability),
         {:ok, export} <- BoxData.request_export(context.organization_id, context.user_id, now) do
      :ok = clean_expired(context.organization_id, now)
      :ok = enqueue(context, export)
      {:ok, view(BoxData.get_export(export.id, context.organization_id) || export, now)}
    end
  end

  def list(context, now \\ DateTime.utc_now()) do
    with :ok <- Organizations.authorize_capability(context, @capability) do
      {:ok, context.organization_id |> BoxData.list_exports() |> Enum.map(&view(&1, now))}
    end
  end

  @doc "Builds one export (the job's work)."
  def build(%{"organization_id" => organization_id, "export_id" => export_id} = args, now) do
    case BoxData.get_export(export_id, organization_id) do
      %{status: "pending"} = export -> run(export, args, now)
      nil -> {:ok, :gone}
      _done -> {:ok, :skipped}
    end
  end

  @doc "Marks an export failed for good (the job's last attempt): the owner may ask again."
  def fail(organization_id, export_id, reason) do
    case BoxData.get_export(export_id, organization_id) do
      %{status: "pending"} = export ->
        BoxData.finish_export(export, %{
          status: "failed",
          error: reason |> inspect() |> String.slice(0, 500)
        })

      _other ->
        {:ok, :skipped}
    end
  end

  # -- building ------------------------------------------------------------

  defp run(export, args, now) do
    organization = %{
      "id" => export.organization_id,
      "slug" => args["slug"],
      "name" => args["name"]
    }

    name = BoxData.file_name(args["slug"] || "box", now)

    with {:ok, scope} <- BoxData.export_context(export, export.requested_by_id),
         {:ok, sections} <- collect(scope),
         {:ok, %{zip: zip} = bundle} <- BoxData.build_bundle(organization, sections, now),
         {:ok, key} <-
           TenantObjectStorage.put_tenant_object(
             export.organization_id,
             BoxData.object_folder(export.id) <> name,
             zip,
             "application/zip"
           ) do
      BoxData.finish_export(export, %{
        status: "ready",
        record_count: bundle.record_count,
        table_count: bundle.table_count,
        file: %{
          "name" => name,
          "key" => key,
          "bytes" => byte_size(zip),
          "sha256" => Base.encode16(:crypto.hash(:sha256, zip), case: :lower)
        },
        completed_at: now,
        expires_at: BoxData.expires_at(now)
      })
    end
  end

  defp collect(scope) do
    modules = Enum.map(TenantDataContexts.purge_sequence(), &elem(&1, 0)) ++ [Organizations]

    Enum.reduce_while(modules, {:ok, []}, fn module, {:ok, sections} ->
      case module.export_tenant_data(scope, :full) do
        {:ok, tables} ->
          {:cont,
           {:ok, sections ++ [%{context: module.tenant_data_policy().context, tables: tables}]}}

        {:error, reason} ->
          {:halt, {:error, {module.tenant_data_policy().context, reason}}}
      end
    end)
  end

  # -- housekeeping ----------------------------------------------------------

  defp clean_expired(organization_id, now) do
    organization_id
    |> BoxData.list_exports()
    |> Enum.filter(&(BoxData.visible_status(&1, now) == "expired"))
    |> Enum.each(fn export ->
      case TenantObjectStorage.delete_tenant_objects_under(
             organization_id,
             BoxData.object_folder(export.id)
           ) do
        {:error, reason} ->
          Logger.warning("box export #{export.id}: expired file not deleted: #{inspect(reason)}")

        _deleted ->
          :ok
      end
    end)
  end

  defp enqueue(context, export) do
    args = %{
      "organization_id" => context.organization_id,
      "export_id" => export.id,
      "slug" => context.organization && context.organization.slug,
      "name" => context.organization && context.organization.name
    }

    if Application.get_env(:palee, :start_oban, true) do
      {:ok, _job} = args |> BoxDataExportJob.new() |> Oban.insert()
      :ok
    else
      _result = build(args, DateTime.utc_now())
      :ok
    end
  end

  # -- shapes ----------------------------------------------------------------

  defp view(export, now) do
    %{
      id: export.id,
      status: BoxData.visible_status(export, now),
      record_count: export.record_count,
      table_count: export.table_count,
      requested_at: export.requested_at,
      completed_at: export.completed_at,
      expires_at: export.expires_at,
      file: if(BoxData.downloadable?(export, now), do: file(export))
    }
  end

  defp file(%{organization_id: organization_id, file: %{"key" => key} = file}) do
    url =
      case TenantObjectStorage.tenant_download_url(organization_id, key) do
        {:ok, url} -> url
        _error -> nil
      end

    %{name: file["name"], bytes: file["bytes"], sha256: file["sha256"], download_url: url}
  end

  defp file(_export), do: nil
end

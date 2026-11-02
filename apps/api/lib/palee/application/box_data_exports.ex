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

  ADR-367: the box's stored files (documents and PDFs, logo, photos and
  videos) go into extra ZIP parts of at most `part_bytes`
  (`config :palee, :box_data_export`), listed as `files` next to the CSV
  ZIP; the owner who asked gets one email when it is ready.
  """

  require Logger

  alias Palee.{BoxData, Email, Identity, Organizations}
  alias Palee.Application.{PublicURL, TenantDataContexts, TenantObjectStorage}
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
           ),
         {:ok, parts} <- pack_files(export, args["slug"] || "box", now),
         {:ok, ready} <-
           BoxData.finish_export(export, %{
             status: "ready",
             record_count: bundle.record_count,
             table_count: bundle.table_count,
             file: stored(name, key, zip),
             parts: parts,
             completed_at: now,
             expires_at: BoxData.expires_at(now)
           }) do
      :ok = notify(ready, args, now)
      {:ok, ready}
    end
  end

  defp stored(name, key, zip) do
    %{
      "name" => name,
      "key" => key,
      "bytes" => byte_size(zip),
      "sha256" => Base.encode16(:crypto.hash(:sha256, zip), case: :lower)
    }
  end

  # -- stored files (ADR-367) --------------------------------------------------

  defp pack_files(export, slug, now) do
    organization_id = export.organization_id

    with {:ok, objects} <- TenantObjectStorage.list_box_files(organization_id) do
      objects
      |> BoxData.select_files(TenantObjectStorage.tenant_object_prefix(organization_id))
      |> BoxData.plan_parts(part_bytes())
      |> Enum.with_index(1)
      |> Enum.reduce_while({:ok, []}, fn {objects, index}, {:ok, parts} ->
        case pack_part(export, BoxData.part_name(slug, now, index), objects) do
          {:ok, part} -> {:cont, {:ok, parts ++ [part]}}
          {:error, _reason} = error -> {:halt, error}
        end
      end)
    end
  end

  defp pack_part(export, name, objects) do
    dir = Path.join(System.tmp_dir!(), "palee-box-export-#{export.id}-#{System.unique_integer([:positive])}")

    try do
      with :ok <- File.mkdir_p(dir),
           {:ok, entries} <- download_all(export.organization_id, objects, dir),
           {:ok, {_name, zip}} <- :zip.create(~c"files.zip", entries, [:memory, cwd: ~c"#{dir}"]),
           {:ok, key} <-
             TenantObjectStorage.put_tenant_object(
               export.organization_id,
               BoxData.object_folder(export.id) <> name,
               zip,
               "application/zip"
             ) do
        {:ok, name |> stored(key, zip) |> Map.put("files", length(entries))}
      end
    after
      File.rm_rf(dir)
    end
  end

  defp download_all(organization_id, objects, dir) do
    Enum.reduce_while(objects, {:ok, []}, fn object, {:ok, entries} ->
      path = Path.join(dir, object.entry)

      with :ok <- File.mkdir_p(Path.dirname(path)),
           :ok <-
             TenantObjectStorage.download_box_file(organization_id, object.bucket, object.key, path) do
        {:cont, {:ok, entries ++ [String.to_charlist(object.entry)]}}
      else
        # A file deleted since it was listed is simply not in the copy.
        {:error, :not_found} -> {:cont, {:ok, entries}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp part_bytes do
    :palee
    |> Application.get_env(:box_data_export, [])
    |> Keyword.get(:part_bytes, 500 * 1024 * 1024)
  end

  # -- the email (ADR-367) -----------------------------------------------------

  # One email to the owner who asked, through the outbox (ADR-203). It
  # carries no download link, only the way to the settings page.
  defp notify(%{requested_by_id: user_id} = export, args, now) when is_binary(user_id) do
    with %{email: email} = account when is_binary(email) <- Identity.find_by_id(user_id),
         {:error, reason} <-
           Email.enqueue(
             :box_data_export_ready,
             email,
             %{
               url: settings_url(args["slug"]),
               box: args["name"] || args["slug"] || "",
               keep_days: BoxData.keep_days()
             },
             locale: account.preferred_locale || "en",
             login_id: account.login_id,
             user_id: user_id,
             idempotency_key: "box_data_export:#{export.id}:ready",
             now: now
           ) do
      Logger.warning("box export #{export.id}: notice not queued: #{inspect(reason)}")
      :ok
    else
      _queued_or_no_address -> :ok
    end
  end

  defp notify(_export, _args, _now), do: :ok

  defp settings_url(slug) when is_binary(slug),
    do: PublicURL.base_url() <> "/org/#{slug}/admin/settings#organization"

  defp settings_url(_slug), do: PublicURL.base_url() <> "/admin/settings#organization"

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
      file: if(BoxData.downloadable?(export, now), do: file(export)),
      parts: if(BoxData.downloadable?(export, now), do: parts(export), else: [])
    }
  end

  defp parts(%{organization_id: organization_id, parts: parts}) when is_list(parts) do
    Enum.map(parts, fn part ->
      %{
        name: part["name"],
        bytes: part["bytes"],
        sha256: part["sha256"],
        files: part["files"],
        download_url: download_url(organization_id, part["key"])
      }
    end)
  end

  defp parts(_export), do: []

  defp download_url(organization_id, key) when is_binary(key) do
    case TenantObjectStorage.tenant_download_url(organization_id, key) do
      {:ok, url} -> url
      _error -> nil
    end
  end

  defp download_url(_organization_id, _key), do: nil

  defp file(%{organization_id: organization_id, file: %{"key" => key} = file}) do
    %{
      name: file["name"],
      bytes: file["bytes"],
      sha256: file["sha256"],
      download_url: download_url(organization_id, key)
    }
  end

  defp file(_export), do: nil
end

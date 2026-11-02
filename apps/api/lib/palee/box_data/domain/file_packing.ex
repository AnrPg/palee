defmodule Palee.BoxData.Domain.FilePacking do
  @moduledoc """
  ADR-367: which stored files go into the box's data export and how they are
  split into ZIP parts.

  * Everything the box stores under its own prefix goes in: documents and
    PDFs (signed documents, invoices, health certificates), the logo and
    other branding, and media (photos and videos of posts, the box page).
  * Earlier exports (`exports/`) never go in.
  * Files are packed in key order into parts of at most `max_bytes`; a file
    bigger than that gets a part of its own. No files, no parts.
  * Inside a part a file keeps its path under the box's prefix, under a
    folder per kind: `documents/…`, `branding/…`, `media/…`. Keys that try to
    climb out (`..`) or are empty are skipped.

  Pure: objects are `%{source, bucket, key, size}` where `source` is
  `:documents`, `:branding` or `:media`.
  """

  @excluded_prefixes ["exports/"]

  @type object :: %{
          source: :documents | :branding | :media,
          bucket: atom(),
          key: String.t(),
          size: non_neg_integer()
        }

  @doc "The objects that belong in the export, each with its `entry` (path inside the ZIP)."
  def select(objects, tenant_prefix) when is_list(objects) and is_binary(tenant_prefix) do
    objects
    |> Enum.flat_map(fn %{key: key} = object ->
      case entry(object.source, tenant_prefix, key) do
        {:ok, entry} -> [Map.put(object, :entry, entry)]
        :skip -> []
      end
    end)
    |> Enum.uniq_by(& &1.entry)
    |> Enum.sort_by(& &1.entry)
  end

  @doc "Splits selected objects into parts of at most `max_bytes` (in order)."
  def plan(objects, max_bytes) when is_list(objects) and is_integer(max_bytes) and max_bytes > 0 do
    objects
    |> Enum.reduce({[], [], 0}, fn object, {parts, current, size} ->
      bytes = object.size || 0

      if current != [] and size + bytes > max_bytes,
        do: {[Enum.reverse(current) | parts], [object], bytes},
        else: {parts, [object | current], size + bytes}
    end)
    |> then(fn
      {parts, [], _size} -> parts
      {parts, current, _size} -> [Enum.reverse(current) | parts]
    end)
    |> Enum.reverse()
  end

  defp entry(source, tenant_prefix, key) when is_binary(key) do
    with true <- String.starts_with?(key, tenant_prefix),
         relative = String.replace_prefix(key, tenant_prefix, ""),
         false <- relative == "" or String.ends_with?(relative, "/"),
         false <- Enum.any?(@excluded_prefixes, &String.starts_with?(relative, &1)),
         segments = String.split(relative, "/"),
         false <- Enum.any?(segments, &(&1 in ["", ".", ".."])) do
      {:ok, "#{source}/#{relative}"}
    else
      _skip -> :skip
    end
  end

  defp entry(_source, _prefix, _key), do: :skip
end

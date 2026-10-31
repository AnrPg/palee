defmodule Palee.BoxData.Domain.CsvBundle do
  @moduledoc """
  ADR-365 (CP-G5): the box's data as one ZIP of CSV files, one per table
  (`<context>/<table>.csv`), plus `manifest.json` (the format, the box,
  when it was made, each file's row count) and `README.txt`.

  * UTF-8 with a byte order mark, so spreadsheet apps read Greek and other
    scripts correctly; comma-separated, RFC 4180 quoting, `\\r\\n` lines.
  * Columns are the union of the rows' keys, sorted; nested values (maps,
    lists) are written as JSON; an empty cell is `null`.
  * A text cell that starts with `=`, `+`, `-`, `@`, a tab or a carriage
    return gets a leading `'`, so a spreadsheet never runs it as a formula
    (CSV injection). The manifest says so.

  Pure apart from OTP's in-memory `:zip`; callers pass the time.
  """

  @format "palee-box-export/v1"
  @bom <<0xEF, 0xBB, 0xBF>>
  @formula_prefixes ["=", "+", "-", "@", "\t", "\r"]

  def format, do: @format

  @doc """
  `{:ok, %{zip, record_count, table_count}}` from sections
  (`[%{context, tables: %{table => [row]}}]`) and the box (`%{id, slug,
  name}`).
  """
  def build(%{organization: organization, generated_at: generated_at, sections: sections}) do
    files =
      for %{context: context, tables: tables} <- sections,
          {table, rows} <- Enum.sort_by(tables, &elem(&1, 0)) do
        {"#{context}/#{table}.csv", rows}
      end

    manifest = %{
      "format" => @format,
      "organization" => organization,
      "generated_at" => DateTime.to_iso8601(generated_at),
      "encoding" => "UTF-8 with BOM, comma-separated, RFC 4180",
      "formula_cells" =>
        "Text cells starting with = + - @ tab or CR are prefixed with ' (CSV injection guard)",
      "nested_values" => "JSON",
      "files" => Enum.map(files, fn {name, rows} -> %{"file" => name, "rows" => length(rows)} end)
    }

    entries =
      [
        {~c"manifest.json", Jason.encode_to_iodata!(manifest, pretty: true)},
        {~c"README.txt", readme(organization, generated_at)}
      ] ++
        Enum.map(files, fn {name, rows} -> {String.to_charlist(name), csv(rows)} end)

    case :zip.create(~c"box-export.zip", Enum.map(entries, &binary_entry/1), [:memory]) do
      {:ok, {_name, zip}} ->
        {:ok,
         %{
           zip: zip,
           record_count: files |> Enum.map(fn {_name, rows} -> length(rows) end) |> Enum.sum(),
           table_count: length(files)
         }}

      {:error, reason} ->
        {:error, {:zip_failed, reason}}
    end
  end

  @doc "One table as CSV (BOM, header, rows)."
  def csv(rows) when is_list(rows) do
    columns =
      rows |> Enum.flat_map(&Map.keys/1) |> Enum.uniq() |> Enum.map(&to_string/1) |> Enum.sort()

    lines =
      [Enum.map(columns, &cell/1)] ++
        Enum.map(rows, fn row ->
          Enum.map(columns, fn column -> row |> fetch(column) |> cell() end)
        end)

    IO.iodata_to_binary([@bom, Enum.map(lines, &[Enum.intersperse(&1, ","), "\r\n"])])
  end

  defp fetch(row, column) do
    case Map.fetch(row, column) do
      {:ok, value} ->
        value

      :error ->
        Enum.find_value(row, fn {key, value} -> if to_string(key) == column, do: value end)
    end
  end

  @doc "One cell: escaped, quoted when needed, formula-guarded."
  def cell(nil), do: ""
  def cell(value) when is_boolean(value), do: to_string(value)
  def cell(value) when is_integer(value) or is_float(value), do: to_string(value)

  def cell(value) when is_map(value) or is_list(value),
    do: value |> Jason.encode!() |> quote_text()

  def cell(value) when is_atom(value), do: value |> Atom.to_string() |> cell()

  def cell(value) when is_binary(value) do
    guarded =
      if String.starts_with?(value, @formula_prefixes), do: "'" <> value, else: value

    quote_text(guarded)
  end

  def cell(value), do: value |> to_string() |> cell()

  defp quote_text(text) do
    if String.contains?(text, [",", "\"", "\n", "\r"]),
      do: "\"" <> String.replace(text, "\"", "\"\"") <> "\"",
      else: text
  end

  defp readme(organization, generated_at) do
    """
    Palee: a copy of the data of #{organization["name"]} (#{organization["slug"]})
    Made #{DateTime.to_iso8601(generated_at)} (UTC).

    One CSV file per table, grouped by area (folder). manifest.json lists the
    files and their row counts. Times are UTC; money is in cents.

    Not included: members' own personal records (journal, wellness, body,
    devices, their own workout logs), which each member downloads from
    Settings; secrets (passwords, keys, tokens); photo and document files
    (their keys are listed in the tables).
    """
  end

  defp binary_entry({name, content}), do: {name, IO.iodata_to_binary(content)}
end

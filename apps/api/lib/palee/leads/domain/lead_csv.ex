defmodule Palee.Leads.Domain.LeadCsv do
  @moduledoc """
  ADR-344: leads from a spreadsheet the box kept before Palee (a sign-up
  sheet, another system's export). Pure: CSV text (parsed by the import
  parser of ADR-254) to one result per row.

  Columns are found by their header, in English or Greek, case and accents
  ignored: name (or first and last name), email, phone, notes, campaign.
  Rows without a name or without an email and phone are reported, not
  imported. At most `max_rows/0` rows per file.
  """

  alias Palee.Imports.Domain.CsvParser
  alias Palee.Leads.Domain.IntakePolicy

  @max_rows 2_000

  @aliases %{
    name: ~w(name full_name fullname ονομα ονοματεπωνυμο),
    first_name: ~w(first_name firstname given_name μικρο_ονομα),
    last_name: ~w(last_name lastname surname family_name επωνυμο),
    email: ~w(email e-mail mail email_address διευθυνση_email),
    phone: ~w(phone mobile telephone tel κινητο τηλεφωνο),
    message: ~w(notes note message comments σημειωσεις σημειωση μηνυμα σχολια),
    campaign: ~w(campaign source πηγη καμπανια)
  }

  def max_rows, do: @max_rows

  @doc """
  `{:ok, [%{row: n, attrs: map} | %{row: n, errors: map}]}` (rows numbered
  from 2, the header being row 1), or `{:error, reason}` for a file that is
  empty, malformed, too long or has no name column.
  """
  @spec parse(String.t()) :: {:ok, [map()]} | {:error, atom()}
  def parse(text) when is_binary(text) do
    with {:ok, %{header: header, rows: rows}} <- CsvParser.parse(text),
         :ok <- within_limit(rows),
         {:ok, columns} <- columns(header) do
      {:ok,
       rows
       |> Enum.with_index(2)
       |> Enum.map(fn {cells, row} -> row(cells, row, columns) end)}
    end
  end

  def parse(_text), do: {:error, :empty_file}

  defp within_limit(rows) when length(rows) > @max_rows, do: {:error, :too_many_rows}
  defp within_limit(_rows), do: :ok

  defp columns(header) do
    keys = Enum.map(header, &key/1)

    columns =
      for {field, names} <- @aliases,
          index = Enum.find_index(keys, &(&1 in names)),
          index != nil,
          into: %{},
          do: {field, index}

    if Map.has_key?(columns, :name) or Map.has_key?(columns, :first_name),
      do: {:ok, columns},
      else: {:error, :missing_name_column}
  end

  defp row(cells, row, columns) do
    cell = fn field ->
      case Map.fetch(columns, field) do
        {:ok, index} -> Enum.at(cells, index)
        :error -> nil
      end
    end

    name =
      cell.(:name) ||
        [cell.(:first_name), cell.(:last_name)]
        |> Enum.reject(&(&1 in [nil, ""]))
        |> Enum.join(" ")

    attrs = %{
      name: name,
      email: cell.(:email),
      phone: cell.(:phone),
      message: cell.(:message),
      campaign: cell.(:campaign)
    }

    case IntakePolicy.normalize(attrs) do
      {:ok, normalized} -> %{row: row, attrs: normalized}
      {:error, {:invalid_fields, errors}} -> %{row: row, errors: errors}
    end
  end

  # "Ονοματεπώνυμο" -> "ονοματεπωνυμο", "E-mail address" -> "e-mail_address".
  defp key(header) do
    header
    |> to_string()
    |> String.trim()
    |> String.downcase()
    |> :unicode.characters_to_nfd_binary()
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.replace(~r/\s+/u, "_")
  end
end

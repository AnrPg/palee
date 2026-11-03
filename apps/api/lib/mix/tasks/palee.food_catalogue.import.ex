defmodule Mix.Tasks.Palee.FoodCatalogue.Import do
  use Mix.Task

  @shortdoc "Imports a licensed product list (barcode, name, brand, size) for barcode scans"

  @moduledoc """
  ADR-421: loads a product list Palee is licensed to reuse into the Greek
  source of the barcode chain (`food_catalogue_products`).

      mix palee.food_catalogue.import FILE.csv --list gr_posokanei \\
        --source "posokanei.gov.gr" --licence "CC BY 4.0" \\
        [--licence-url https://…]

  The CSV (UTF-8, `,` `;` or tab) has a header with `barcode` and `name`,
  optionally `brand` and `quantity`. Barcodes failing the GS1 check digit and
  shop codes are skipped and counted. Re-importing a list replaces its rows.
  Only import a list whose licence allows this use, and give that licence.
  """

  alias Palee.Imports.Domain.CsvParser
  alias Palee.Infrastructure.Nutrition.EctoFoodCatalogue
  alias Palee.Nutrition

  @switches [list: :string, source: :string, licence: :string, licence_url: :string]

  @impl Mix.Task
  def run(args) do
    case OptionParser.parse(args, strict: @switches) do
      {opts, [path], []} -> import!(path, opts)
      _other -> usage!()
    end
  end

  defp import!(path, opts) do
    list = opts[:list] || usage!()
    source = opts[:source] || usage!()
    licence = opts[:licence] || usage!()

    Mix.Task.run("app.start")

    {:ok, %{header: header, rows: rows}} =
      path |> File.read!() |> CsvParser.parse() |> ok_or_raise()

    columns = header |> Enum.map(&(&1 |> String.trim() |> String.downcase())) |> Enum.with_index()
    at = Map.new(columns)

    Enum.each(
      ~w(barcode name),
      &(Map.has_key?(at, &1) || Mix.raise("The CSV needs a #{&1} column"))
    )

    {products, skipped} =
      Enum.reduce(rows, {%{}, 0}, fn row, {products, skipped} ->
        with {:ok, code} <- Nutrition.parse_barcode(cell(row, at, "barcode") || ""),
             name when is_binary(name) <- cell(row, at, "name") do
          product = %{
            list: list,
            barcode: code,
            name: name,
            brand: cell(row, at, "brand"),
            quantity: cell(row, at, "quantity"),
            source_name: source,
            licence: licence,
            licence_url: opts[:licence_url]
          }

          {Map.put(products, code, product), skipped}
        else
          _skip -> {products, skipped + 1}
        end
      end)

    case EctoFoodCatalogue.import_list(Map.values(products), DateTime.utc_now()) do
      {:ok, count} ->
        Mix.shell().info("Imported #{count} products into #{list}; skipped #{skipped} rows")

      {:error, changeset} ->
        Mix.raise("Invalid row: #{inspect(changeset.changes)} #{inspect(changeset.errors)}")
    end
  end

  defp cell(row, at, column) do
    with index when is_integer(index) <- Map.get(at, column),
         value when is_binary(value) <- Enum.at(row, index),
         trimmed when trimmed != "" <- String.trim(value) do
      trimmed
    else
      _blank -> nil
    end
  end

  defp ok_or_raise({:ok, parsed}), do: {:ok, parsed}
  defp ok_or_raise({:error, reason}), do: Mix.raise("Could not read the CSV: #{reason}")

  defp usage! do
    Mix.raise(
      "Usage: mix palee.food_catalogue.import FILE.csv --list NAME --source SOURCE " <>
        "--licence LICENCE [--licence-url URL]"
    )
  end
end

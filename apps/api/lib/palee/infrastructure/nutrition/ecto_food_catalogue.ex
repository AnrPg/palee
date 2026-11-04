defmodule Palee.Infrastructure.Nutrition.EctoFoodCatalogue do
  @moduledoc """
  Licensed product lists (ADR-421), the Greek source of the chain: no Greek
  source offers an open API with barcodes, so a list Palee may reuse (e.g.
  the ministry's posokanei.gov.gr product list under a reuse licence, Ν.
  4727/2020) is imported into `food_catalogue_products` and looked up here.
  An empty table answers "not found" at once. Name, brand and size only:
  these lists carry no nutrition.
  """

  @behaviour Palee.Nutrition.Ports.FoodDatabase

  import Ecto.Query

  alias Palee.Nutrition.CatalogueProduct
  alias Palee.Nutrition.Domain.FoodProduct
  alias Palee.Repo

  @impl true
  def lookup(barcode, _language) do
    CatalogueProduct
    |> where([p], p.barcode == ^barcode)
    |> order_by([p], asc: p.list)
    |> limit(1)
    |> Repo.one()
    |> case do
      nil ->
        {:error, :not_found}

      product ->
        {:ok,
         product
         |> FoodProduct.from_catalogue()
         |> Map.merge(%{
           source: "catalogue",
           attribution: %{
             "source" => product.source_name,
             "licence" => product.licence,
             "licence_url" => product.licence_url
           }
         })}
    end
  end

  @doc "Inserts or replaces one list's products. Returns `{:ok, count}` or the first invalid row."
  def import_list(rows, now) do
    changesets = Enum.map(rows, &CatalogueProduct.changeset/1)

    case Enum.find(changesets, &(not &1.valid?)) do
      nil ->
        entries =
          Enum.map(changesets, fn changeset ->
            changeset
            |> Ecto.Changeset.apply_changes()
            |> Map.from_struct()
            |> Map.drop([:__meta__])
            |> Map.merge(%{inserted_at: now, updated_at: now})
          end)

        count =
          entries
          |> Enum.chunk_every(1_000)
          |> Enum.reduce(0, fn chunk, acc ->
            {inserted, _rows} =
              Repo.insert_all(CatalogueProduct, chunk,
                on_conflict: {:replace_all_except, [:list, :barcode, :inserted_at]},
                conflict_target: [:list, :barcode]
              )

            acc + inserted
          end)

        {:ok, count}

      invalid ->
        {:error, invalid}
    end
  end
end

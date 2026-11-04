defmodule Palee.Infrastructure.Programmes.EctoProgrammeCatalogue do
  @moduledoc """
  The cross-business programme catalogue (ADR-370) through the
  `palee_marketplace_programmes` SECURITY DEFINER projection.
  """

  @behaviour Palee.Programmes.Ports.Catalogue

  alias Palee.Repo

  @columns ~w(id organization_id organization_slug organization_name title summary level goal
              equipment sessions_per_week price_cents currency weeks version_number
              rating_average rating_count published_at equipment_removed facts
              cover_object_key)a

  @impl true
  def search(filters) do
    %{rows: rows} =
      Ecto.Adapters.SQL.query!(
        Repo,
        "SELECT * FROM palee_marketplace_programmes($1, $2, $3, $4, $5)",
        [
          filters[:query],
          filters[:goal],
          filters[:level],
          filters[:limit] || 20,
          filters[:offset] || 0
        ]
      )

    Enum.map(rows, fn row ->
      @columns
      |> Enum.zip(row)
      |> Map.new()
      |> Map.update!(:id, &Ecto.UUID.cast!/1)
      |> Map.update!(:organization_id, &Ecto.UUID.cast!/1)
      |> Map.update!(:rating_average, &(&1 && Decimal.to_float(&1)))
    end)
  end
end

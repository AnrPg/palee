defmodule Palee.Infrastructure.HelpCentre.DatabaseHelpIndex do
  @moduledoc """
  `ArticleSearchIndex` straight over the database (ADR-362): reads the
  published rows and ranks them with `Domain.Ranking`. The sandbox adapter
  for dev and tests, and enough for a few hundred articles anywhere.
  """

  @behaviour Palee.HelpCentre.Ports.ArticleSearchIndex

  alias Palee.HelpCentre
  alias Palee.HelpCentre.ArticleStore

  @impl true
  def search(params) do
    rows = ArticleStore.list_published(Map.get(params, :locales, ["en"]))

    {:ok,
     HelpCentre.rank(rows, Map.get(params, :q),
       screen: Map.get(params, :screen),
       limit: Map.get(params, :limit, 10) * 2
     )}
  end

  @impl true
  def replace(_articles), do: :ok
end

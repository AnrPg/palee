defmodule Palee.HelpCentre.Ports.ArticleSearchIndex do
  @moduledoc """
  Full-text search over published help articles (ADR-362). Meilisearch in
  production; a database adapter in dev and tests. When the index fails the
  application ranks the database rows itself (`Domain.Ranking`), so search
  never goes down with the index.

  `params`: `q`, `locales` (the reader's then English), `audience`,
  `screen`, `feature_key`, `limit`. Returns article maps (as stored).
  """

  @callback search(map()) :: {:ok, [map()]} | {:error, term()}
  @doc "Replaces the index with these published articles."
  @callback replace([map()]) :: :ok | {:error, term()}
end

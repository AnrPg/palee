defmodule Palee.HelpCentre.Ports.ArticleStore do
  @moduledoc """
  Persistence of help articles (ADR-362). Platform content: reads of
  published articles need no session; drafts and writes run in the Palee
  team's session (the facade opens it from the context's `user_id`).
  """

  @type context :: map() | nil

  @doc "Published rows in any of `locales`."
  @callback list_published([String.t()]) :: [map()]
  @doc "Every row (drafts too), optionally filtered by `locale`, `status`, `slug`."
  @callback list_all(context(), map()) :: [map()]
  @callback get(context(), slug :: String.t(), locale :: String.t()) :: map() | nil
  @callback upsert(context(), slug :: String.t(), locale :: String.t(), map()) ::
              {:ok, map()} | {:error, term()}
  @callback delete(context(), slug :: String.t(), locale :: String.t()) :: :ok | {:error, :not_found}
  @doc "Seeds rows: inserts new ones, updates `source = seed` rows of a lower version."
  @callback seed(context(), [map()]) :: %{inserted: non_neg_integer(), updated: non_neg_integer()}
end

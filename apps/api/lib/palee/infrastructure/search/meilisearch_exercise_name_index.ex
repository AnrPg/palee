defmodule Palee.Infrastructure.Search.MeilisearchExerciseNameIndex do
  @moduledoc """
  ADR-461: exercise-name suggestions from Meilisearch (index
  `exercise_names`). Postgres stays the source of truth: a remembered name
  is upserted there first, then pushed here best-effort (a rebuild repairs a
  missed push). Documents are `{id, name, normalized, aliases, scope,
  organization_id, user_id, catalog_slug, category, uses_count}`; `scope`,
  `organization_id` and `user_id` are filterable and every search filters on
  them, so a person never sees another's names nor a box it is not in. Typo
  tolerance starts at three letters; Greek words have English synonyms.

  When Meilisearch cannot answer, the search falls back to
  `PostgresExerciseNameIndex`.
  """

  @behaviour Palee.Application.Ports.ExerciseNameIndex

  require Logger

  alias Palee.Infrastructure.Search.PostgresExerciseNameIndex, as: Postgres
  alias Palee.Workouts.Domain.ExerciseNames

  @index "exercise_names"
  @ranking_rules ~w(words typo proximity attribute sort exactness uses_count:desc)

  @impl true
  defdelegate enqueue_record(owner, rows, increment), to: Postgres

  @impl true
  def record(owner, entries, increment) do
    with {:ok, %{saved: saved, new: new}} <- Postgres.upsert(owner, entries, increment) do
      warn_on_error(push(Enum.map(saved, &row_document/1)))
      {:ok, new}
    end
  end

  @impl true
  def refresh_catalog(catalog) do
    warn_on_error(push(Enum.map(catalog, &catalog_document/1)))
    :ok
  end

  defp warn_on_error(:ok), do: :ok

  defp warn_on_error({:error, reason}) do
    Logger.warning("exercise names not pushed to Meilisearch: #{inspect(reason)}")
    :ok
  end

  @impl true
  def search(viewer, query, limit, catalog) do
    case meili_search(viewer, query, limit, catalog) do
      {:ok, hits} ->
        {:ok, hits}

      {:error, reason} ->
        if config()[:log_failures] != false,
          do: Logger.info("exercise suggestions from Postgres: #{inspect(reason)}")

        Postgres.search(viewer, query, limit, catalog)
    end
  end

  @impl true
  def rebuild(owners, catalog) do
    documents =
      Enum.map(catalog, &catalog_document/1) ++
        Enum.map(Postgres.owner_rows(owners), &row_document/1)

    with :ok <- ensure_settings(),
         {:ok, %Req.Response{status: status}} when status in 200..299 <-
           request(:delete, index_path("/documents")),
         :ok <- push(documents) do
      {:ok, length(documents)}
    else
      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:meilisearch_status, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp meili_search(viewer, query, limit, catalog) do
    take = limit + 5
    filters = filters(viewer)

    body = %{
      queries:
        Enum.map(filters, fn {_source, filter} ->
          %{indexUid: @index, q: query, filter: filter, limit: take}
        end)
    }

    case request(:post, "/multi-search", json: body) do
      {:ok, %Req.Response{status: status, body: %{"results" => results}}}
      when status in 200..299 and is_list(results) ->
        hits =
          filters
          |> Enum.zip(results)
          |> Map.new(fn {{source, _filter}, result} -> {source, hits(result)} end)

        {:ok, complete(hits, query, take, catalog)}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:meilisearch_status, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # An index the rebuild never seeded still answers the catalog, in memory.
  defp complete(hits, query, take, catalog) do
    hits = Map.merge(%{mine: [], box: [], palee: []}, hits)

    if hits.palee == [],
      do: %{hits | palee: Postgres.catalog_hits(query, take, catalog)},
      else: hits
  end

  defp filters(%{user_id: user_id} = viewer) do
    mine = {:mine, "scope = \"user\" AND user_id = \"#{user_id}\""}
    palee = {:palee, "scope = \"palee\""}

    case viewer[:organization_id] do
      organization_id when is_binary(organization_id) ->
        [mine, {:box, "scope = \"org\" AND organization_id = \"#{organization_id}\""}, palee]

      _none ->
        [mine, palee]
    end
  end

  defp hits(%{"hits" => hits}) when is_list(hits) do
    Enum.flat_map(hits, fn
      %{"name" => name} = hit when is_binary(name) ->
        [
          %{
            name: name,
            catalog_slug: hit["catalog_slug"],
            uses_count: hit["uses_count"] || 0,
            category: hit["category"]
          }
        ]

      _other ->
        []
    end)
  end

  defp hits(_result), do: []

  defp push([]), do: :ok

  defp push(documents) do
    with :ok <- ensure_settings() do
      case request(:post, index_path("/documents"), json: documents) do
        {:ok, %Req.Response{status: status}} when status in 200..299 ->
          :ok

        {:ok, %Req.Response{status: status, body: body}} ->
          {:error, {:meilisearch_status, status, body}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp ensure_settings do
    body = %{
      searchableAttributes: ["name", "aliases", "normalized"],
      filterableAttributes: ["scope", "organization_id", "user_id"],
      rankingRules: @ranking_rules,
      typoTolerance: %{enabled: true, minWordSizeForTypos: %{oneTypo: 3, twoTypos: 7}},
      synonyms: synonyms()
    }

    case request(:patch, index_path("/settings"), json: body) do
      {:ok, %Req.Response{status: status}} when status in 200..299 ->
        :ok

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:meilisearch_status, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp synonyms do
    Map.new(ExerciseNames.word_synonyms(), fn {word, english} -> {word, [english]} end)
  end

  defp catalog_document(doc) do
    %{
      id: "palee-#{doc.catalog_slug}",
      scope: "palee",
      name: doc.name,
      normalized: ExerciseNames.fold(doc.name),
      aliases: doc.aliases,
      catalog_slug: doc.catalog_slug,
      category: doc.category,
      organization_id: nil,
      user_id: nil,
      uses_count: 0
    }
  end

  defp row_document(row) do
    %{
      id: row.id,
      scope: row.scope,
      name: row.name,
      normalized: row.folded,
      aliases: [],
      catalog_slug: row.catalog_slug,
      category: nil,
      organization_id: row.organization_id,
      user_id: row.user_id,
      uses_count: row.uses_count
    }
  end

  defp request(method, path, opts \\ []) do
    Req.request(
      Keyword.merge(
        [
          method: method,
          url: url(path),
          headers: headers(),
          receive_timeout: 1_500,
          retry: false
        ],
        opts
      )
    )
  end

  defp headers do
    case config()[:api_key] do
      nil -> []
      "" -> []
      api_key -> [{"authorization", "Bearer #{api_key}"}]
    end
  end

  defp index_path(suffix), do: "/indexes/#{@index}#{suffix}"
  defp url(path), do: String.trim_trailing(config()[:url] || "http://localhost:7700", "/") <> path
  defp config, do: Application.get_env(:palee, :meilisearch, [])
end

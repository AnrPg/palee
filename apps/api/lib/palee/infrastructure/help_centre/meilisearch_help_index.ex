defmodule Palee.Infrastructure.HelpCentre.MeilisearchHelpIndex do
  @moduledoc """
  `ArticleSearchIndex` over Meilisearch (ADR-362): one document per
  published article and locale, typo tolerant, filtered by locale and
  audience. Uses the shared `:meilisearch` config (`help_index` names the
  index, default `help_articles`; `req_options` for tests).
  """

  @behaviour Palee.HelpCentre.Ports.ArticleSearchIndex

  @searchable ~w(title keywords summary body)
  @filterable ~w(locale audience feature_key slug)
  @fields ~w(slug locale title summary body audience feature_key guide_id screens keywords position complete updated_at)a

  @impl true
  def search(params) do
    filters =
      [
        "locale IN [#{Enum.map_join(Map.get(params, :locales, ["en"]), ", ", &quoted/1)}]",
        audience_filter(Map.get(params, :audience)),
        feature_filter(Map.get(params, :feature_key))
      ]
      |> Enum.reject(&is_nil/1)

    body = %{q: Map.get(params, :q) || "", limit: Map.get(params, :limit, 10) * 2, filter: filters}

    case request(:post, "/indexes/#{index()}/search", json: body) do
      {:ok, %Req.Response{status: status, body: %{"hits" => hits}}} when status in 200..299 ->
        {:ok, Enum.map(hits, &from_hit/1)}

      {:ok, %Req.Response{status: status}} ->
        {:error, {:meilisearch_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def replace(articles) do
    documents = Enum.map(articles, &document/1)

    with {:ok, _settings} <-
           ok(
             request(:patch, "/indexes/#{index()}/settings",
               json: %{searchableAttributes: @searchable, filterableAttributes: @filterable}
             )
           ),
         {:ok, _deleted} <- ok(request(:delete, "/indexes/#{index()}/documents")),
         {:ok, _added} <-
           ok(request(:post, "/indexes/#{index()}/documents?primaryKey=id", json: documents)) do
      :ok
    end
  end

  defp document(article) do
    article
    |> Map.take(@fields)
    |> Map.put(:id, "#{article.slug}__#{String.replace(article.locale, "-", "_")}")
  end

  defp from_hit(hit) do
    Map.new(@fields, fn field -> {field, Map.get(hit, Atom.to_string(field))} end)
  end

  defp audience_filter(nil), do: nil
  defp audience_filter(audience), do: "audience IN [#{quoted(audience)}, \"all\"]"

  defp feature_filter(nil), do: nil
  defp feature_filter(feature), do: "feature_key = #{quoted(feature)}"

  defp quoted(value), do: Jason.encode!(to_string(value))

  defp ok({:ok, %Req.Response{status: status} = response}) when status in 200..299,
    do: {:ok, response}

  defp ok({:ok, %Req.Response{status: status}}), do: {:error, {:meilisearch_status, status}}
  defp ok({:error, reason}), do: {:error, reason}

  defp request(method, path, opts \\ []) do
    Req.request(
      [
        method: method,
        url: String.trim_trailing(config()[:url] || "http://localhost:7700", "/") <> path,
        headers: headers(),
        receive_timeout: 1_500,
        retry: false
      ]
      |> Keyword.merge(opts)
      |> Keyword.merge(config()[:req_options] || [])
    )
  end

  defp headers do
    case config()[:api_key] do
      key when is_binary(key) and key != "" -> [{"authorization", "Bearer #{key}"}]
      _none -> []
    end
  end

  defp index, do: config()[:help_index] || "help_articles"
  defp config, do: Application.get_env(:palee, :meilisearch, [])
end

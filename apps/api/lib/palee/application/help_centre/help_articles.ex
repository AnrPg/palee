defmodule Palee.Application.HelpCentre.HelpArticles do
  @moduledoc """
  Reading the help centre (ADR-362): public, no sign-in.

    * `search/1` – `q`, `locale`, `audience` (staff | member), `screen`
      (the app path the reader is on: its articles rank first), `feature`
      and `limit` (1..20, default 10). Searches the index and, when the
      index is down, ranks the database rows instead.
    * `for_screen/1` – the articles linked from one screen (`path`), for
      the «?» of that screen.
    * `show/2` – one article in a locale, else in English (`fallback`).
    * `retrieve/2` – the articles the support assistant may answer from
      (ADR-363), with bodies.
  """

  require Logger

  alias Palee.HelpCentre

  @default_limit 10
  @max_limit 20

  def search(params) when is_map(params) do
    with {:ok, query} <- query(params) do
      {:ok, %{locale: query.locale, articles: Enum.map(find(query), &HelpCentre.public_article/1)}}
    end
  end

  def search(_params), do: {:error, :bad_request}

  def for_screen(params) when is_map(params) do
    with {:ok, query} <- query(params),
         path when is_binary(path) and path != "" <- query.screen do
      articles =
        query.locales
        |> HelpCentre.list_published()
        |> Enum.filter(&HelpCentre.on_screen?(&1, path))
        |> HelpCentre.localize(query.locale)
        |> Enum.filter(&HelpCentre.for_audience?(&1, query.audience))
        |> Enum.sort_by(&{&1.position, &1.slug})
        |> Enum.take(query.limit)

      {:ok, %{locale: query.locale, articles: Enum.map(articles, &HelpCentre.public_article/1)}}
    else
      {:error, _reason} = error -> error
      _missing -> {:error, {:invalid_fields, %{screen: ["required"]}}}
    end
  end

  def show(slug, locale) do
    locale = HelpCentre.locale(locale)

    with true <- HelpCentre.valid_slug?(slug),
         [article] <-
           [locale, HelpCentre.fallback_locale()]
           |> Enum.uniq()
           |> HelpCentre.list_published()
           |> Enum.filter(&(&1.slug == slug))
           |> HelpCentre.localize(locale) do
      {:ok, HelpCentre.public_article(article)}
    else
      _missing -> {:error, :not_found}
    end
  end

  @doc "Top articles for a support question (bodies included), for staff."
  def retrieve(question, opts) do
    {:ok, query} =
      query(%{
        "q" => question,
        "locale" => Keyword.get(opts, :locale),
        "screen" => Keyword.get(opts, :screen),
        "audience" => "staff",
        "limit" => Keyword.get(opts, :limit, 4)
      })

    found = find(query)

    # A question in other words than the articles still gets the screen's
    # own articles to answer from.
    if found == [] and is_binary(query.screen) do
      case for_screen(%{"screen" => query.screen, "locale" => query.locale, "limit" => 2}) do
        {:ok, %{articles: articles}} -> articles
        _error -> []
      end
    else
      Enum.map(found, &HelpCentre.public_article/1)
    end
  end

  defp find(query) do
    params = %{
      q: query.q,
      locales: query.locales,
      audience: query.audience,
      screen: query.screen,
      feature_key: query.feature,
      limit: query.limit
    }

    rows =
      case HelpCentre.search_index(params) do
        {:ok, rows} ->
          rows

        {:error, reason} ->
          Logger.warning("help search index unavailable: #{inspect(reason)}")

          query.locales
          |> HelpCentre.list_published()
          |> HelpCentre.rank(query.q, screen: query.screen, limit: query.limit * 2)
      end

    # Keep the ranked order; one row per article, in the reader's locale.
    order = rows |> Enum.map(& &1.slug) |> Enum.uniq()
    localized = rows |> HelpCentre.localize(query.locale) |> Map.new(&{&1.slug, &1})

    order
    |> Enum.map(&Map.get(localized, &1))
    |> Enum.reject(&is_nil/1)
    |> Enum.filter(&HelpCentre.for_audience?(&1, query.audience))
    |> Enum.filter(&(is_nil(query.feature) or Map.get(&1, :feature_key) == query.feature))
    |> Enum.take(query.limit)
  end

  defp query(params) do
    params = Map.new(params, fn {k, v} -> {to_string(k), v} end)
    locale = HelpCentre.locale(Map.get(params, "locale"))
    audience = Map.get(params, "audience")
    limit = integer(Map.get(params, "limit"), @default_limit)

    cond do
      not is_nil(audience) and audience not in ["staff", "member"] ->
        {:error, {:invalid_fields, %{audience: ["invalid"]}}}

      limit not in 1..@max_limit ->
        {:error, {:invalid_fields, %{limit: ["invalid"]}}}

      true ->
        {:ok,
         %{
           q: text(Map.get(params, "q"), 200),
           locale: locale,
           locales: Enum.uniq([locale, HelpCentre.fallback_locale()]),
           audience: audience,
           screen: text(Map.get(params, "screen"), 300),
           feature: text(Map.get(params, "feature"), 48),
           limit: limit
         }}
    end
  end

  defp integer(nil, default), do: default
  defp integer(value, _default) when is_integer(value), do: value

  defp integer(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} -> number
      _other -> default
    end
  end

  defp integer(_value, default), do: default

  defp text(value, max) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> String.slice(trimmed, 0, max)
    end
  end

  defp text(_value, _max), do: nil
end

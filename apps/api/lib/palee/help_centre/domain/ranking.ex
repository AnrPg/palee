defmodule Palee.HelpCentre.Domain.Ranking do
  @moduledoc """
  Ranks help articles for a query (ADR-362), pure. Used by the database
  search adapter and as the fallback when the search index is down.

  Matching ignores case and accents (Greek tonos included) and needs
  every query word of three or more letters to start a word of the
  article (prefix match, so «πακέτ» finds «πακέτα»). Weights: title 4,
  keywords 3, summary 2, body 1; an article linked from the reader's
  screen gets a boost. An empty query lists articles in their `position`
  order, screen-linked ones first.
  """

  alias Palee.HelpCentre.Domain.ArticlePolicy

  @screen_boost 5

  def rank(articles, query, opts \\ []) do
    screen = Keyword.get(opts, :screen)
    limit = Keyword.get(opts, :limit, 10)
    terms = terms(query)

    articles
    |> Enum.map(fn article -> {score(article, terms, screen), article} end)
    |> Enum.filter(fn {score, _article} -> terms == [] or score > 0 end)
    |> Enum.sort_by(fn {score, article} ->
      {-score, Map.get(article, :position, 100), article.slug}
    end)
    |> Enum.take(limit)
    |> Enum.map(&elem(&1, 1))
  end

  @doc "The normalised search words of a text: lower case, no accents, 3+ letters."
  def terms(nil), do: []

  def terms(text) when is_binary(text) do
    text
    |> normalize()
    |> String.split(~r/[^\p{L}\p{N}]+/u, trim: true)
    |> Enum.filter(&(String.length(&1) >= 3))
    |> Enum.uniq()
  end

  def normalize(text) do
    text
    |> String.downcase()
    |> :unicode.characters_to_nfd_binary()
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.replace("ς", "σ")
  end

  defp score(article, [], screen), do: screen_boost(article, screen)

  defp score(article, terms, screen) do
    fields = [
      {words(article.title), 4},
      {words(Enum.join(Map.get(article, :keywords) || [], " ")), 3},
      {words(article.summary), 2},
      {words(article.body), 1}
    ]

    matches =
      Enum.map(terms, fn term ->
        fields
        |> Enum.filter(fn {words, _weight} ->
          Enum.any?(words, &String.starts_with?(&1, term))
        end)
        |> Enum.map(&elem(&1, 1))
        |> Enum.sum()
      end)

    if Enum.all?(matches, &(&1 > 0)),
      do: Enum.sum(matches) + screen_boost(article, screen),
      else: 0
  end

  defp screen_boost(_article, nil), do: 0

  defp screen_boost(article, screen),
    do: if(ArticlePolicy.on_screen?(article, screen), do: @screen_boost, else: 0)

  defp words(nil), do: []

  defp words(text) do
    text |> normalize() |> String.split(~r/[^\p{L}\p{N}]+/u, trim: true)
  end
end

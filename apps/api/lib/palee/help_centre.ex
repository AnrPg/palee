defmodule Palee.HelpCentre do
  @moduledoc """
  The help centre (ADR-362): articles written once per feature, in the 12
  app locales, searchable and linked from the screens they explain. The
  Palee team writes them; anyone can read the published ones.
  """

  alias Palee.HelpCentre.ArticleStore
  alias Palee.HelpCentre.Domain.{ArticlePolicy, Ranking, Seed}

  defdelegate locales(), to: ArticlePolicy
  defdelegate statuses(), to: ArticlePolicy
  defdelegate audiences(), to: ArticlePolicy
  defdelegate locale(value), to: ArticlePolicy
  defdelegate fallback_locale(), to: ArticlePolicy
  defdelegate valid_slug?(slug), to: ArticlePolicy
  defdelegate localize(rows, locale), to: ArticlePolicy
  defdelegate on_screen?(article, path), to: ArticlePolicy
  defdelegate for_audience?(article, audience), to: ArticlePolicy
  defdelegate public_article(article), to: ArticlePolicy, as: :public
  defdelegate console_article(article), to: ArticlePolicy, as: :console
  defdelegate write_attrs(existing, params, actor_id, now), to: ArticlePolicy
  defdelegate rank(articles, query, opts \\ []), to: Ranking
  defdelegate seed_rows(file, now), to: Seed, as: :rows

  defdelegate list_published(locales), to: ArticleStore
  defdelegate list_all(context, filters), to: ArticleStore
  defdelegate get_article(context, slug, locale), to: ArticleStore, as: :get
  defdelegate upsert_article(context, slug, locale, attrs), to: ArticleStore, as: :upsert
  defdelegate delete_article(context, slug, locale), to: ArticleStore, as: :delete
  defdelegate seed(context, rows), to: ArticleStore

  @doc "Searches the index; `{:error, _}` when the index is down."
  def search_index(params), do: index().search(params)

  @doc "Replaces the search index with every published article."
  def reindex, do: index().replace(ArticleStore.list_published(locales()))

  defp index, do: Application.fetch_env!(:palee, :help_search_index)
end

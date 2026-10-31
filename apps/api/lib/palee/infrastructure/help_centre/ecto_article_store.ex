defmodule Palee.Infrastructure.HelpCentre.EctoArticleStore do
  @moduledoc "Ecto adapter of `HelpCentre.Ports.ArticleStore` (ADR-362)."

  @behaviour Palee.HelpCentre.Ports.ArticleStore

  import Ecto.Query

  alias Palee.HelpCentre.Article
  alias Palee.Repo

  @impl true
  def list_published(locales) do
    Article
    |> where([a], a.status == "published" and a.locale in ^locales)
    |> order_by([a], asc: a.position, asc: a.slug)
    |> Repo.all()
  end

  @impl true
  def list_all(_context, filters) do
    filters
    |> Enum.reduce(Article, fn
      {:locale, locale}, query when is_binary(locale) -> where(query, [a], a.locale == ^locale)
      {:status, status}, query when is_binary(status) -> where(query, [a], a.status == ^status)
      {:slug, slug}, query when is_binary(slug) -> where(query, [a], a.slug == ^slug)
      _other, query -> query
    end)
    |> order_by([a], asc: a.position, asc: a.slug, asc: a.locale)
    |> Repo.all()
  end

  @impl true
  def get(_context, slug, locale), do: Repo.get_by(Article, slug: slug, locale: locale)

  @impl true
  def upsert(context, slug, locale, attrs) do
    (get(context, slug, locale) || %Article{slug: slug, locale: locale})
    |> Article.changeset(attrs)
    |> Repo.insert_or_update()
  end

  @impl true
  def delete(context, slug, locale) do
    case get(context, slug, locale) do
      nil ->
        {:error, :not_found}

      article ->
        {:ok, _deleted} = Repo.delete(article)
        :ok
    end
  end

  # A seed row never overwrites the Palee team's own edits (source palee)
  # nor a newer seed.
  @impl true
  def seed(context, rows) do
    Enum.reduce(rows, %{inserted: 0, updated: 0}, fn row, counts ->
      case get(context, row.slug, row.locale) do
        nil ->
          {:ok, _article} = %Article{} |> Article.changeset(row) |> Repo.insert()
          %{counts | inserted: counts.inserted + 1}

        %Article{source: "seed", version: version} = article when version < row.version ->
          {:ok, _article} = article |> Article.changeset(row) |> Repo.update()
          %{counts | updated: counts.updated + 1}

        _kept ->
          counts
      end
    end)
  end
end

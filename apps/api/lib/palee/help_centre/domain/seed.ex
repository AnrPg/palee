defmodule Palee.HelpCentre.Domain.Seed do
  @moduledoc """
  The help centre's starting articles (ADR-362), pure: turns the seed file
  (`priv/help_centre/articles.json`, generated from the feature catalog and
  the in-app guides by `apps/web/scripts/build-help-seed.ts`) into rows.

  File shape: `{"version": n, "articles": [{"slug", "audience",
  "feature_key", "guide_id", "screens", "keywords", "position",
  "locales": {"el": {"title", "summary", "body", "complete"}, ...}}]}`.
  Every row is published and marked `source: "seed"` with the file's
  version, so a newer seed refreshes untouched rows and never overwrites
  an article the Palee team has edited.
  """

  alias Palee.HelpCentre.Domain.ArticlePolicy

  def rows(%{"version" => version, "articles" => articles}, %DateTime{} = now)
      when is_integer(version) and is_list(articles) do
    rows =
      for article <- articles,
          {locale, text} <- Map.get(article, "locales", %{}),
          locale in ArticlePolicy.locales() do
        %{
          slug: Map.fetch!(article, "slug"),
          locale: locale,
          title: Map.fetch!(text, "title"),
          summary: Map.fetch!(text, "summary"),
          body: Map.get(text, "body", ""),
          complete: Map.get(text, "complete", true),
          audience: Map.get(article, "audience", "staff"),
          feature_key: Map.get(article, "feature_key"),
          guide_id: Map.get(article, "guide_id"),
          screens: Map.get(article, "screens", []),
          keywords: Map.get(text, "keywords", Map.get(article, "keywords", [])),
          position: Map.get(article, "position", 100),
          status: "published",
          source: "seed",
          version: version,
          published_at: now
        }
      end

    if Enum.all?(rows, &ArticlePolicy.valid_slug?(&1.slug)),
      do: {:ok, rows},
      else: {:error, :invalid_seed}
  end

  def rows(_file, _now), do: {:error, :invalid_seed}
end

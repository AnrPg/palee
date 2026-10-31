defmodule Palee.Application.HelpCentre.PlatformHelpArticles do
  @moduledoc """
  The Palee team's help centre console (ADR-362): every article in every
  locale with drafts, writing one locale of an article, deleting it,
  seeding the starting set and rebuilding the search index. Vendors only
  (`PlatformContext`); writes run in the vendor's session, so the row
  policies check it again.
  """

  alias Palee.HelpCentre
  alias Palee.Organizations.PlatformContext

  def list(%PlatformContext{} = platform, params) do
    filters = %{
      locale: Map.get(params, "locale") || Map.get(params, :locale),
      status: Map.get(params, "status") || Map.get(params, :status),
      slug: Map.get(params, "slug") || Map.get(params, :slug)
    }

    {:ok,
     %{
       articles: platform |> scope() |> HelpCentre.list_all(filters) |> Enum.map(&console/1)
     }}
  end

  def list(_context, _params), do: {:error, :vendor_required}

  def save(platform, slug, locale, params, now \\ DateTime.utc_now())

  def save(%PlatformContext{} = platform, slug, locale, params, now) do
    context = scope(platform)

    with :ok <- valid_key(slug, locale),
         existing = HelpCentre.get_article(context, slug, locale),
         {:ok, attrs} <- HelpCentre.write_attrs(existing, params, platform.user_id, now),
         {:ok, article} <- HelpCentre.upsert_article(context, slug, locale, attrs) do
      _ = HelpCentre.reindex()
      {:ok, console(article)}
    end
  end

  def save(_context, _slug, _locale, _params, _now), do: {:error, :vendor_required}

  def delete(%PlatformContext{} = platform, slug, locale) do
    with :ok <- valid_key(slug, locale),
         :ok <- HelpCentre.delete_article(scope(platform), slug, locale) do
      _ = HelpCentre.reindex()
      {:ok, %{deleted: true}}
    end
  end

  def delete(_context, _slug, _locale), do: {:error, :vendor_required}

  @doc "Rebuilds the search index from the published articles."
  def reindex(%PlatformContext{}) do
    case HelpCentre.reindex() do
      :ok -> {:ok, %{reindexed: true}}
      {:error, _reason} -> {:error, :search_index_unavailable}
    end
  end

  def reindex(_context), do: {:error, :vendor_required}

  @doc """
  Seeds the starting articles from the decoded seed file (system or
  vendor); never overwrites the team's edits.
  """
  def seed(context, file, now \\ DateTime.utc_now()) do
    with {:ok, rows} <- HelpCentre.seed_rows(file, now) do
      counts = HelpCentre.seed(seed_scope(context), rows)
      _ = HelpCentre.reindex()
      {:ok, counts}
    end
  end

  defp seed_scope(%PlatformContext{} = platform), do: scope(platform)
  defp seed_scope(_system), do: nil

  defp scope(%PlatformContext{user_id: user_id}), do: %{user_id: user_id}

  defp console(article), do: HelpCentre.console_article(article)

  defp valid_key(slug, locale) do
    cond do
      not HelpCentre.valid_slug?(slug) -> {:error, {:invalid_fields, %{slug: ["invalid"]}}}
      locale not in HelpCentre.locales() -> {:error, {:invalid_fields, %{locale: ["invalid"]}}}
      true -> :ok
    end
  end
end

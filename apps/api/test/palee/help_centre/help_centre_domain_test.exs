defmodule Palee.HelpCentre.DomainTest do
  @moduledoc "ADR-362: article rules, screen links, ranking and the seed, pure."

  use ExUnit.Case, async: true

  alias Palee.HelpCentre.Domain.{ArticlePolicy, Ranking, Seed}

  defp article(attrs) do
    Map.merge(
      %{slug: "a", locale: "en", title: "T", summary: "S", body: "", keywords: [], screens: [], audience: "staff", position: 100, guide_id: nil, feature_key: nil},
      attrs
    )
  end

  test "screen patterns match a path and what is below it, with :params" do
    assert ArticlePolicy.screen_matches?("/admin/shop", "/admin/shop")
    assert ArticlePolicy.screen_matches?("/admin/shop", "/admin/shop/orders?tab=1")
    assert ArticlePolicy.screen_matches?("/admin/users/:id", "/admin/users/42/finance")
    refute ArticlePolicy.screen_matches?("/admin/shop", "/admin/shopping")
    refute ArticlePolicy.screen_matches?("/admin/shop", "/admin")
  end

  test "localize keeps the reader's locale and falls back to English" do
    rows = [article(%{slug: "a", locale: "en"}), article(%{slug: "a", locale: "el"}), article(%{slug: "b", locale: "en"})]

    assert [%{slug: "a", locale: "el", fallback: false}, %{slug: "b", locale: "en", fallback: true}] =
             rows |> ArticlePolicy.localize("el") |> Enum.sort_by(& &1.slug)
  end

  test "locales normalise to the 12 app locales" do
    assert ArticlePolicy.locale("pt_PT") == "pt-PT"
    assert ArticlePolicy.locale("el-GR") == "el"
    assert ArticlePolicy.locale("xx") == "en"
    assert ArticlePolicy.locale(nil) == "en"
  end

  test "writes are validated; HTML is refused; first publication is stamped" do
    now = ~U[2026-10-31 10:00:00Z]

    assert {:ok, attrs} =
             ArticlePolicy.write_attrs(nil, %{"title" => "Τιμές", "summary" => "Πώς", "status" => "published", "screens" => ["/admin/finance"]}, "v", now)

    assert attrs.published_at == now and attrs.version == 1 and attrs.source == "palee"

    assert {:error, {:invalid_fields, %{body: ["invalid"]}}} =
             ArticlePolicy.write_attrs(nil, %{"title" => "x", "summary" => "y", "body" => "<script>x</script>"}, "v", now)

    assert {:error, {:invalid_fields, errors}} =
             ArticlePolicy.write_attrs(nil, %{"title" => "", "summary" => "y", "screens" => ["no-slash"], "guide_id" => "Bad"}, "v", now)

    assert Map.keys(errors) |> Enum.sort() == [:guide_id, :screens, :title]
  end

  test "ranking ignores accents and case, weights titles and boosts the reader's screen" do
    rows = [
      article(%{slug: "pkg", title: "Πακέτα συνδρομής", body: "Δημιούργησε πακέτο"}),
      article(%{slug: "shop", title: "Κατάστημα", body: "Πούλα πακέτα πρωτεΐνης", screens: ["/admin/shop"]}),
      article(%{slug: "other", title: "Άλλο", body: "τίποτα"})
    ]

    assert ["pkg", "shop"] = rows |> Ranking.rank("ΠΑΚΕΤΑ") |> Enum.map(& &1.slug)
    assert ["shop", "pkg"] = rows |> Ranking.rank("πακετα", screen: "/admin/shop") |> Enum.map(& &1.slug)
    assert [] = Ranking.rank(rows, "ανύπαρκτο")
    assert ["shop", "other", "pkg"] |> length() == rows |> Ranking.rank("", screen: "/admin/shop") |> length()
  end

  test "the seed file becomes published seed rows" do
    file = %{
      "version" => 2,
      "articles" => [
        %{"slug" => "guide-shop-staff", "guide_id" => "shop_staff", "screens" => ["/admin/shop"], "locales" => %{"el" => %{"title" => "Κατάστημα", "summary" => "Σ"}, "xx" => %{"title" => "?", "summary" => "?"}}}
      ]
    }

    assert {:ok, [row]} = Seed.rows(file, ~U[2026-10-31 10:00:00Z])
    assert %{slug: "guide-shop-staff", locale: "el", status: "published", source: "seed", version: 2} = row
    assert {:error, :invalid_seed} = Seed.rows(%{"articles" => []}, ~U[2026-10-31 10:00:00Z])
  end

  test "the shipped seed file is valid and covers all 12 locales" do
    file = "priv/help_centre/articles.json" |> File.read!() |> Jason.decode!()
    assert {:ok, rows} = Seed.rows(file, ~U[2026-10-31 10:00:00Z])

    for {slug, locales} <- Enum.group_by(rows, & &1.slug, & &1.locale) do
      assert Enum.sort(locales) == Enum.sort(ArticlePolicy.locales()), "#{slug} misses a locale"
    end
  end
end

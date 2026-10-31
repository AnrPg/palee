defmodule PaleeWeb.HelpCentreControllerTest do
  @moduledoc """
  ADR-362 over HTTP: the public help centre (search, a screen's «?»,
  one article with the English fallback) and the vendors' console (write a
  locale, drafts stay hidden, delete, reindex). Requests run as the
  RLS-enforcing role.
  """

  use PaleeWeb.ConnCase, async: false

  import Palee.TestFixtures

  alias Palee.Application.HelpCentre.SeedHelpCentre
  alias Palee.Organizations

  setup do
    {:ok, counts} = SeedHelpCentre.call()
    vendor = user_fixture(%{nickname: "help_vendor_#{System.unique_integer([:positive])}"})
    {:ok, _vendor} = Organizations.grant_vendor(vendor.id)
    %{vendor: vendor, seeded: counts, outsider: user_fixture()}
  end

  test "the seed is complete: 19 articles in 12 locales", %{seeded: counts} do
    assert counts.inserted == 19 * 12
  end

  test "search ranks in the reader's language, filtered by audience", %{conn: conn} do
    body =
      conn
      |> get("/api/public/help/articles", %{q: "coupons", locale: "en", audience: "staff"})
      |> json_response(200)

    assert body["locale"] == "en"
    assert [%{"slug" => "guide-finance-offers"} | _] = body["articles"]
    assert Enum.all?(body["articles"], &(&1["audience"] in ["staff", "all"]))

    greek = conn |> recycle() |> get("/api/public/help/articles", %{locale: "el", limit: 3}) |> json_response(200)
    assert greek["locale"] == "el"
    assert length(greek["articles"]) == 3

    assert %{"errors" => [_ | _]} =
             conn |> recycle() |> get("/api/public/help/articles", %{limit: 99}) |> json_response(422)
  end

  test "a screen's «?» lists its articles; one article falls back to English", %{conn: conn} do
    body =
      conn
      |> get("/api/public/help/screen", %{path: "/admin/finance", locale: "el"})
      |> json_response(200)

    slugs = Enum.map(body["articles"], & &1["slug"])
    assert "feature-finance" in slugs and "guide-finance-offers" in slugs

    article =
      conn |> recycle() |> get("/api/public/help/articles/guide-finance-offers", %{locale: "de"}) |> json_response(200)

    assert article["slug"] == "guide-finance-offers"
    assert article["guide_id"] == "finance_offers"
    assert is_binary(article["body"])

    assert conn |> recycle() |> get("/api/public/help/articles/no-such-article") |> json_response(404)
  end

  test "only vendors use the console", %{conn: conn, outsider: outsider} do
    assert %{"code" => "vendor_required"} =
             conn |> put_bearer_token(outsider) |> get("/api/platform/help/articles") |> json_response(403)
  end

  test "a vendor writes a draft, publishes it, deletes it", %{conn: conn, vendor: vendor} do
    path = "/api/platform/help/articles/check-in-kiosk/el"

    draft =
      conn
      |> put_bearer_token(vendor)
      |> put(path, %{
        title: "Είσοδος με tablet",
        summary: "Πώς ανοίγει η είσοδος στο tablet της υποδοχής.",
        body: "1. Άνοιξε τις Ρυθμίσεις.\n2. Πάτα «Είσοδος».",
        audience: "staff",
        screens: ["/admin/check-in"],
        keywords: ["tablet", "kiosk"],
        status: "draft"
      })
      |> json_response(200)

    assert draft["status"] == "draft"

    hidden = conn |> recycle() |> get("/api/public/help/articles/check-in-kiosk", %{locale: "el"})
    assert json_response(hidden, 404)

    conn |> recycle() |> put_bearer_token(vendor) |> put(path, %{status: "published"}) |> json_response(200)

    shown = conn |> recycle() |> get("/api/public/help/articles", %{q: "tablet", locale: "el"}) |> json_response(200)
    assert "check-in-kiosk" in Enum.map(shown["articles"], & &1["slug"])

    listed =
      conn |> recycle() |> put_bearer_token(vendor) |> get("/api/platform/help/articles", %{slug: "check-in-kiosk"}) |> json_response(200)

    assert [%{"locale" => "el", "status" => "published"}] = listed["articles"]

    assert %{"deleted" => true} =
             conn |> recycle() |> put_bearer_token(vendor) |> delete(path) |> json_response(200)

    assert %{"reindexed" => true} =
             conn |> recycle() |> put_bearer_token(vendor) |> post("/api/platform/help/reindex") |> json_response(200)

    assert conn |> recycle() |> get("/api/public/help/articles/check-in-kiosk", %{locale: "el"}) |> json_response(404)
  end

  test "HTML and bad keys are refused", %{conn: conn, vendor: vendor} do
    response =
      conn
      |> put_bearer_token(vendor)
      |> put("/api/platform/help/articles/new-one/en", %{
        title: "Hi",
        summary: "Short",
        body: "<script>alert(1)</script>",
        status: "draft"
      })

    assert json_response(response, 422)

    assert conn
           |> recycle()
           |> put_bearer_token(vendor)
           |> put("/api/platform/help/articles/new-one/xx", %{title: "Hi", summary: "Short"})
           |> json_response(422)
  end
end

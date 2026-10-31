defmodule PaleeWeb.FoodsControllerTest do
  @moduledoc """
  ADR-376: barcode lookups (sandbox food database), the cache outbox, own
  foods and what a member sees of the numbers. ConnCase: real RLS.
  """

  use PaleeWeb.ConnCase, async: false

  import Palee.TestFixtures

  alias Palee.Application.{Foods, SetWellnessPreferences}
  alias Palee.Identity.UserContext
  alias Palee.{Nutrition, Organizations, Repo}

  @yoghurt "5201054014615"
  @unknown "5201234500006"
  @down "9990000000012"

  setup do
    Repo.query!("DELETE FROM food_products")
    :ok
  end

  test "a scan finds the product, credits Open Food Facts and hides the numbers by default", %{conn: conn} do
    member = user_fixture()

    assert %{
             "status" => "found",
             "source" => "open_food_facts",
             "macros_visible" => false,
             "food" => %{"name" => "Γιαούρτι στραγγιστό 2%", "portion_hint" => "protein", "nutrients" => nil},
             "attribution" => %{"licence" => "ODbL-1.0", "url" => url}
           } = conn |> as(member) |> get("/api/me/foods/barcode/#{@yoghurt}") |> json_response(200)

    assert url =~ @yoghurt
    assert %{status: "found"} = Nutrition.FoodStore.get_cached(@yoghurt)

    # The cache answers the second scan; who scanned is never stored.
    assert %{"status" => "found"} =
             conn |> as(user_fixture()) |> get("/api/me/foods/barcode/#{@yoghurt}") |> json_response(200)

    %{columns: columns} = Repo.query!("SELECT * FROM food_products LIMIT 0")
    refute "user_id" in columns
  end

  test "unknown products, shop codes and bad scans", %{conn: conn} do
    member = user_fixture()

    assert %{"status" => "manual", "reason" => "not_found", "food" => nil} =
             conn |> as(member) |> get("/api/me/foods/barcode/#{@unknown}") |> json_response(200)

    assert %{"status" => "manual", "reason" => "in_store_code"} =
             conn |> as(member) |> get("/api/me/foods/barcode/2001234000000") |> json_response(200)

    assert %{"code" => "invalid_barcode"} =
             conn |> as(member) |> get("/api/me/foods/barcode/5201054014618") |> json_response(422)
  end

  test "a failed lookup is left to the outbox", %{conn: conn} do
    member = user_fixture()

    assert %{"status" => "pending"} =
             conn |> as(member) |> get("/api/me/foods/barcode/#{@down}") |> json_response(200)

    assert %{status: "pending", attempts: 1, last_error: error} = Nutrition.FoodStore.get_cached(@down)
    assert error =~ "sandbox_down"

    # Not due yet: the worker leaves it alone.
    assert {:ok, 0} = Foods.process_due()

    Repo.query!("UPDATE food_products SET next_attempt_at = now() - interval '1 minute'")
    assert {:ok, 1} = Foods.process_due()
    assert %{status: "pending", attempts: 2} = Nutrition.FoodStore.get_cached(@down)
  end

  test "own foods: the manual entry wins over the database and stays private", %{conn: conn} do
    member = user_fixture()
    other = user_fixture()

    assert %{"food" => %{"id" => id, "portion_hint" => "carbs", "barcode" => @unknown}} =
             conn
             |> as(member)
             |> send_json(:post, "/api/me/foods", %{
               name: "Παξιμάδι γιαγιάς",
               barcode: @unknown,
               nutrients: %{carbohydrates: 70, proteins: 10, fat: 3}
             })
             |> json_response(201)

    assert %{"status" => "found", "source" => "custom", "food" => %{"id" => ^id}} =
             conn |> as(member) |> get("/api/me/foods/barcode/#{@unknown}") |> json_response(200)

    assert %{"status" => "manual"} =
             conn |> as(other) |> get("/api/me/foods/barcode/#{@unknown}") |> json_response(200)

    assert %{"foods" => [%{"name" => "Παξιμάδι γιαγιάς"}]} =
             conn |> as(member) |> get("/api/me/foods") |> json_response(200)

    assert %{"foods" => []} = conn |> as(other) |> get("/api/me/foods") |> json_response(200)

    assert %{"food" => %{"name" => "Παξιμάδι", "barcode" => @unknown}} =
             conn
             |> as(member)
             |> send_json(:patch, "/api/me/foods/#{id}", %{name: "Παξιμάδι"})
             |> json_response(200)

    assert conn |> as(other) |> send_json(:patch, "/api/me/foods/#{id}", %{name: "x"}) |> json_response(404)
    assert conn |> as(other) |> delete("/api/me/foods/#{id}") |> json_response(404)

    assert %{"code" => "invalid_nutrients"} =
             conn
             |> as(member)
             |> send_json(:post, "/api/me/foods", %{name: "X", nutrients: %{fat: 150}})
             |> json_response(422)

    assert conn |> as(member) |> delete("/api/me/foods/#{id}") |> response(204)
  end

  test "macros show only with a coach's plan that sets them, and not when hidden", %{conn: conn} do
    admin = admin_fixture()
    {:ok, _} = Organizations.ensure_legacy_membership_for_migration(admin, :owner)
    member = user_fixture()
    {:ok, _} = Organizations.ensure_legacy_membership_for_migration(member, :member)

    {:ok, context} =
      Organizations.resolve_tenant_context(admin, Organizations.legacy_organization_slug())

    {:ok, _plan} =
      Nutrition.put_plan(context, member.id, %{
        "title" => "Plan",
        "body" => "Eat well",
        "protein_grams" => 140
      })

    assert %{"macros_visible" => true, "food" => %{"nutrients" => %{"proteins" => 10.0}}} =
             conn |> as(member) |> get("/api/me/foods/barcode/#{@yoghurt}") |> json_response(200)

    {:ok, _prefs} = SetWellnessPreferences.call(UserContext.new(member), %{"hide_macros" => true})

    assert %{"macros_visible" => false, "food" => %{"nutrients" => nil}} =
             conn |> as(member) |> get("/api/me/foods/barcode/#{@yoghurt}") |> json_response(200)
  end

  defp as(conn, user), do: conn |> recycle() |> put_bearer_token(user)

  defp send_json(conn, method, path, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> dispatch(@endpoint, method, path, Jason.encode!(body))
  end
end

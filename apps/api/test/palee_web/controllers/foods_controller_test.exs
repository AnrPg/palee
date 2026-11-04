defmodule PaleeWeb.FoodsControllerTest do
  @moduledoc """
  ADR-376: barcode lookups (sandbox food database), the cache outbox, own
  foods and what a member sees of the numbers. ADR-421: sources other than
  Open Food Facts, barcodes nobody had, and «Φωτογραφία ετικέτας».
  ConnCase: real RLS.
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
    Repo.query!("DELETE FROM food_barcode_misses")
    :ok
  end

  test "a scan finds the product, credits Open Food Facts and hides the numbers by default", %{
    conn: conn
  } do
    member = user_fixture()

    assert %{
             "status" => "found",
             "source" => "open_food_facts",
             "macros_visible" => false,
             "food" => %{
               "name" => "Γιαούρτι στραγγιστό 2%",
               "portion_hint" => "protein",
               "nutrients" => nil
             },
             "attribution" => %{"licence" => "ODbL-1.0", "url" => url}
           } =
             conn |> as(member) |> get("/api/me/foods/barcode/#{@yoghurt}") |> json_response(200)

    assert url =~ @yoghurt
    assert %{status: "found"} = Nutrition.FoodStore.get_cached(@yoghurt)

    # The cache answers the second scan; who scanned is never stored.
    assert %{"status" => "found"} =
             conn
             |> as(user_fixture())
             |> get("/api/me/foods/barcode/#{@yoghurt}")
             |> json_response(200)

    %{columns: columns} = Repo.query!("SELECT * FROM food_products LIMIT 0")
    refute "user_id" in columns
  end

  test "unknown products, shop codes and bad scans", %{conn: conn} do
    member = user_fixture()

    assert %{"status" => "manual", "reason" => "not_found", "food" => nil} =
             conn |> as(member) |> get("/api/me/foods/barcode/#{@unknown}") |> json_response(200)

    assert %{"status" => "manual", "reason" => "in_store_code"} =
             conn
             |> as(member)
             |> get("/api/me/foods/barcode/2001234000000")
             |> json_response(200)

    assert %{"code" => "invalid_barcode"} =
             conn
             |> as(member)
             |> get("/api/me/foods/barcode/5201054014618")
             |> json_response(422)
  end

  test "a failed lookup is left to the outbox", %{conn: conn} do
    member = user_fixture()

    assert %{"status" => "pending"} =
             conn |> as(member) |> get("/api/me/foods/barcode/#{@down}") |> json_response(200)

    assert %{status: "pending", attempts: 1, last_error: error} =
             Nutrition.FoodStore.get_cached(@down)

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

    assert conn
           |> as(other)
           |> send_json(:patch, "/api/me/foods/#{id}", %{name: "x"})
           |> json_response(404)

    assert conn |> as(other) |> delete("/api/me/foods/#{id}") |> json_response(404)

    assert %{"errors" => [%{"source" => %{"pointer" => "/nutrients/fat"}}]} =
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

  test "a product cached from USDA carries USDA's credit and source", %{conn: conn} do
    now = DateTime.utc_now()

    Repo.insert!(%Nutrition.CachedFood{
      barcode: @unknown,
      status: "found",
      source: "usda_fdc",
      name: "OATS",
      nutrients: %{"proteins" => 13.0},
      fetched_at: now
    })

    assert %{
             "status" => "found",
             "source" => "usda_fdc",
             "food" => %{"name" => "OATS"},
             "attribution" => %{"source" => "USDA FoodData Central", "licence" => "CC0-1.0"}
           } =
             conn
             |> as(user_fixture())
             |> get("/api/me/foods/barcode/#{@unknown}")
             |> json_response(200)
  end

  test "a scan nobody had is counted per country, never per person", %{conn: conn} do
    greek = user_fixture()
    put_home_country(greek, "GR")
    nowhere = user_fixture()

    for member <- [greek, greek, nowhere] do
      assert %{"status" => "manual", "reason" => "not_found", "label_reading" => true} =
               conn
               |> as(member)
               |> get("/api/me/foods/barcode/#{@unknown}")
               |> json_response(200)
    end

    # Found products, shop codes and a source that is down are not misses.
    conn |> as(greek) |> get("/api/me/foods/barcode/#{@yoghurt}") |> json_response(200)
    conn |> as(greek) |> get("/api/me/foods/barcode/2001234000000") |> json_response(200)
    conn |> as(greek) |> get("/api/me/foods/barcode/#{@down}") |> json_response(200)

    %{columns: columns, rows: rows} =
      Repo.query!("SELECT * FROM food_barcode_misses ORDER BY country")

    assert Enum.sort(columns) == ~w(barcode country first_seen_on last_seen_on scans)
    assert [[@unknown, "", 1 | _], [@unknown, "GR", 2 | _]] = rows

    vendor = user_fixture()
    bypass_rls(fn -> {:ok, _vendor} = Organizations.grant_vendor(vendor.id) end)

    assert %{"code" => "vendor_required"} =
             conn |> as(greek) |> get("/api/platform/food-misses") |> json_response(403)

    assert %{"misses" => [%{"barcode" => @unknown, "country" => "GR", "scans" => 2}, _empty]} =
             conn |> as(vendor) |> get("/api/platform/food-misses") |> json_response(200)

    assert %{"misses" => [%{"country" => "GR"}]} =
             conn
             |> as(vendor)
             |> get("/api/platform/food-misses?country=gr")
             |> json_response(200)
  end

  describe "«Φωτογραφία ετικέτας»" do
    setup do
      on_exit(fn -> Application.delete_env(:palee, :fake_food_label_reader) end)
      :ok
    end

    test "reads the label into the own food's prefill; nothing is saved", %{conn: conn} do
      member = user_fixture()

      assert %{
               "macros_visible" => false,
               "food" => %{
                 "name" => "Φέτα ΠΟΠ",
                 "brand" => "Sandbox Dairy",
                 "serving_label" => "1 φέτα (30 g)",
                 "portion_hint" => "fat",
                 "nutrients" => nil
               }
             } =
               conn
               |> as(member)
               |> post_label(front: jpeg(), nutrition: jpeg())
               |> json_response(200)

      assert_received {:label_read, 2, "en", %{feature: "food_label", organization_id: nil}}
      assert %{"foods" => []} = conn |> as(member) |> get("/api/me/foods") |> json_response(200)
      refute_received {:label_read, _, _, %{user_id: nil}}
    end

    test "the numbers show where macros may show", %{conn: conn} do
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
          "fat_grams" => 60
        })

      assert %{"macros_visible" => true, "food" => %{"nutrients" => nutrients}} =
               conn |> as(member) |> post_label(nutrition: jpeg()) |> json_response(200)

      assert nutrients == %{
               "proteins" => 17.0,
               "fat" => 21.5,
               "carbohydrates" => 1.0,
               "salt" => 3.0
             }

      refute Map.has_key?(nutrients, "energy")
    end

    test "no photo, a wrong file, an unreadable label, and reading switched off", %{conn: conn} do
      member = user_fixture()

      assert %{"code" => "invalid_label_photo"} =
               conn |> as(member) |> post_label([]) |> json_response(422)

      assert %{"code" => "invalid_label_photo"} =
               conn
               |> as(member)
               |> post_label(front: upload("text/plain", "hello"))
               |> json_response(422)

      Application.put_env(:palee, :fake_food_label_reader, :unreadable)

      assert %{"code" => "label_unreadable"} =
               conn |> as(member) |> post_label(front: jpeg()) |> json_response(422)

      Application.put_env(:palee, :fake_food_label_reader, :off)

      assert %{"code" => "label_reading_unavailable"} =
               conn |> as(member) |> post_label(front: jpeg()) |> json_response(503)

      assert %{"status" => "manual", "label_reading" => false} =
               conn
               |> as(member)
               |> get("/api/me/foods/barcode/#{@unknown}")
               |> json_response(200)
    end
  end

  defp post_label(conn, photos) do
    conn
    |> put_req_header("content-type", "multipart/form-data; boundary=test")
    |> post("/api/me/foods/label-read", photos |> Map.new(fn {k, v} -> {to_string(k), v} end))
  end

  defp jpeg, do: upload("image/jpeg", <<0xFF, 0xD8, 0xFF, 0xE0, "label">>)

  defp upload(type, bytes) do
    path = Path.join(System.tmp_dir!(), "label-#{System.unique_integer([:positive])}")
    File.write!(path, bytes)
    on_exit(fn -> File.rm(path) end)
    %Plug.Upload{path: path, filename: "label.jpg", content_type: type}
  end

  defp put_home_country(user, country) do
    hood = Ecto.UUID.generate()

    bypass_rls(fn ->
      Repo.query!(
        """
        INSERT INTO places_neighbourhoods
          (id, slug, kind, name, name_en, country_code, latitude, longitude, radius_m,
           search_key, inserted_at, updated_at)
        VALUES ($1, $2, 'neighbourhood', 'Κυψέλη', 'Kypseli', $3, 38.0, 23.73, 800,
                'kypseli', now(), now())
        """,
        [Ecto.UUID.dump!(hood), "kypseli-#{System.unique_integer([:positive])}", country]
      )

      Repo.query!(
        """
        INSERT INTO user_home_areas (id, user_id, neighbourhood_id, position, inserted_at, updated_at)
        VALUES ($1, $2, $3, 0, now(), now())
        """,
        [Ecto.UUID.dump!(Ecto.UUID.generate()), Ecto.UUID.dump!(user.id), Ecto.UUID.dump!(hood)]
      )
    end)
  end

  defp as(conn, user), do: conn |> recycle() |> put_bearer_token(user)

  defp send_json(conn, method, path, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> dispatch(@endpoint, method, path, Jason.encode!(body))
  end
end

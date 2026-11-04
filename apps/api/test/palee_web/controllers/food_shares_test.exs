defmodule PaleeWeb.FoodSharesTest do
  @moduledoc """
  ADR-421 addendum: «Μοιράσου το». An own food with a barcode reaches every
  member (the public cache, source `palee_members`) and Open Food Facts only
  when the person ticks it; never over a product a public source or an
  earlier share has; who shared is kept for abuse handling only. ConnCase:
  real RLS; Open Food Facts writes through a `Req.Test` stub.
  """

  use PaleeWeb.ConnCase, async: false

  import Palee.TestFixtures

  alias Palee.Application.Foods
  alias Palee.Nutrition.FoodStore
  alias Palee.Repo

  @yoghurt "5201054014615"
  @unknown "5201234500006"
  @other "5201234500013"

  setup do
    Repo.query!("DELETE FROM food_product_shares")
    Repo.query!("DELETE FROM food_products")
    Repo.query!("DELETE FROM food_barcode_misses")
    :ok
  end

  defp save(conn, member, body) do
    conn |> as(member) |> send_json(:post, "/api/me/foods", body)
  end

  defp shares do
    %{rows: rows} =
      Repo.query!("SELECT barcode, user_id, name, off_status FROM food_product_shares")

    rows
  end

  test "unticked, an own food stays private exactly as before", %{conn: conn} do
    member = user_fixture()

    assert %{"food" => %{"shared_at" => nil}} =
             conn
             |> save(member, %{name: "Παξιμάδι", barcode: @unknown, share: false})
             |> json_response(201)

    assert %{"status" => "manual"} =
             conn
             |> as(user_fixture())
             |> get("/api/me/foods/barcode/#{@unknown}")
             |> json_response(200)

    assert shares() == []
  end

  test "ticked, the product (and nothing about the person) reaches the next scan by anyone", %{
    conn: conn
  } do
    member = user_fixture()

    assert %{"status" => "manual", "reason" => "not_found"} =
             conn |> as(member) |> get("/api/me/foods/barcode/#{@unknown}") |> json_response(200)

    assert %{"food" => %{"shared_at" => shared_at}} =
             conn
             |> save(member, %{
               name: "Παξιμάδι γιαγιάς",
               brand: "Φούρνος",
               barcode: @unknown,
               serving_label: "2 φέτες",
               note: "του πρωινού",
               nutrients: %{carbohydrates: 70, proteins: 10, fat: 3},
               share: true
             })
             |> json_response(201)

    assert is_binary(shared_at)

    body =
      conn
      |> as(user_fixture())
      |> get("/api/me/foods/barcode/#{@unknown}")
      |> json_response(200)

    assert %{
             "status" => "found",
             "source" => "palee_members",
             "food" => %{"name" => "Παξιμάδι γιαγιάς", "brand" => "Φούρνος", "id" => nil},
             "attribution" => %{"source" => "Palee members", "licence" => "ODbL-1.0"}
           } = body

    refute Jason.encode!(body) =~ member.id
    refute Jason.encode!(body) =~ "πρωινού"

    member_id = Ecto.UUID.dump!(member.id)
    assert [[@unknown, ^member_id, "Παξιμάδι γιαγιάς", "queued"]] = shares()
  end

  test "a public product is never overwritten and the first share wins", %{conn: conn} do
    first = user_fixture()
    second = user_fixture()

    # Open Food Facts already has the yoghurt.
    conn |> as(first) |> get("/api/me/foods/barcode/#{@yoghurt}") |> json_response(200)

    assert %{"food" => %{"shared_at" => nil}} =
             conn
             |> save(first, %{name: "Άλλο όνομα", barcode: @yoghurt, share: true})
             |> json_response(201)

    assert %{source: "open_food_facts", name: "Γιαούρτι στραγγιστό 2%"} =
             FoodStore.get_cached(@yoghurt)

    assert %{"food" => %{"shared_at" => at}} =
             conn
             |> save(first, %{name: "Πρώτο", barcode: @other, share: true})
             |> json_response(201)

    assert is_binary(at)

    assert %{"food" => %{"shared_at" => nil}} =
             conn
             |> save(second, %{name: "Δεύτερο", barcode: @other, share: true})
             |> json_response(201)

    assert %{source: "palee_members", name: "Πρώτο"} = FoodStore.get_cached(@other)
    assert [[@other, _id, "Πρώτο", "queued"]] = shares()
  end

  test "only a product barcode can be shared", %{conn: conn} do
    member = user_fixture()

    assert %{"code" => "share_needs_barcode"} =
             conn |> save(member, %{name: "Τυρί", share: true}) |> json_response(422)

    assert %{"code" => "share_needs_barcode"} =
             conn
             |> save(member, %{name: "Τυρί", barcode: "2001234000000", share: true})
             |> json_response(422)

    assert %{"foods" => []} = conn |> as(member) |> get("/api/me/foods") |> json_response(200)
  end

  test "an own food can be shared later from its edit", %{conn: conn} do
    member = user_fixture()

    assert %{"food" => %{"id" => id}} =
             conn |> save(member, %{name: "Κριθαράκι", barcode: @unknown}) |> json_response(201)

    assert %{"food" => %{"shared_at" => at}} =
             conn
             |> as(member)
             |> send_json(:patch, "/api/me/foods/#{id}", %{share: true})
             |> json_response(200)

    assert is_binary(at)
    assert %{source: "palee_members", status: "found"} = FoodStore.get_cached(@unknown)
  end

  describe "the Open Food Facts outbox" do
    setup %{conn: conn} do
      member = user_fixture()

      conn
      |> save(member, %{
        name: "Παξιμάδι",
        brand: "Φούρνος",
        barcode: @unknown,
        nutrients: %{carbohydrates: 70, proteins: 10},
        share: true
      })
      |> json_response(201)

      %{member: member}
    end

    test "sends the product only, with Palee's account and app fields", %{member: member} do
      test = self()

      Req.Test.stub(Palee.OpenFoodFactsWrite, fn conn ->
        case {conn.method, conn.request_path} do
          {"GET", "/api/v2/product/" <> _} ->
            Req.Test.json(conn, %{"status" => 0})

          {"POST", "/cgi/product_jqm2.pl"} ->
            {:ok, body, conn} = Plug.Conn.read_body(conn)

            send(
              test,
              {:form, URI.decode_query(body), Plug.Conn.get_req_header(conn, "user-agent")}
            )

            Req.Test.json(conn, %{"status" => 1, "status_verbose" => "fields saved"})
        end
      end)

      assert {:ok, 1} = Foods.process_shares()
      assert_received {:form, form, [agent]}

      assert agent =~ "Palee"

      assert %{
               "code" => @unknown,
               "user_id" => "palee-test",
               "password" => "test-password",
               "app_name" => "Palee",
               "lang" => "en",
               "product_name_en" => "Παξιμάδι",
               "brands" => "Φούρνος",
               "nutrition_data_per" => "100g",
               "nutriment_carbohydrates" => carbs,
               "nutriment_carbohydrates_unit" => "g",
               "nutriment_proteins" => _proteins,
               "app_uuid" => uuid
             } = form

      assert carbs in ["70", "70.0"]
      refute uuid == member.id
      refute Map.has_key?(form, "nutriment_fat")
      refute Enum.any?(Map.values(form), &(&1 == member.id))
      assert [[@unknown, _id, _name, "sent"]] = shares()

      # Nothing left to send.
      assert {:ok, 0} = Foods.process_shares()
    end

    test "a product Open Food Facts has already ends as exists, nothing is written" do
      Req.Test.stub(Palee.OpenFoodFactsWrite, fn conn ->
        assert conn.method == "GET"
        Req.Test.json(conn, %{"status" => 1, "product" => %{"code" => @unknown}})
      end)

      assert {:ok, 1} = Foods.process_shares()
      assert [[@unknown, _id, _name, "exists"]] = shares()
    end

    test "a busy server is retried later; a refusal is final" do
      Req.Test.stub(Palee.OpenFoodFactsWrite, &Plug.Conn.send_resp(&1, 503, "busy"))

      assert {:ok, 1} = Foods.process_shares()
      assert [[@unknown, _id, _name, "queued"]] = shares()
      # Backed off: not due yet.
      assert {:ok, 0} = Foods.process_shares()

      Repo.query!(
        "UPDATE food_product_shares SET off_next_attempt_at = now() - interval '1 minute'"
      )

      Req.Test.stub(Palee.OpenFoodFactsWrite, &Plug.Conn.send_resp(&1, 403, "no"))
      assert {:ok, 1} = Foods.process_shares()
      assert [[@unknown, _id, _name, "failed"]] = shares()
    end

    test "without Palee's account nothing is sent and the share waits" do
      config = Application.get_env(:palee, :open_food_facts_contributions)
      on_exit(fn -> Application.put_env(:palee, :open_food_facts_contributions, config) end)

      Application.put_env(
        :palee,
        :open_food_facts_contributions,
        Keyword.put(config, :password, nil)
      )

      assert {:ok, 0} = Foods.process_shares()
      assert [[@unknown, _id, _name, "queued"]] = shares()
    end
  end

  defp as(conn, user), do: conn |> recycle() |> put_bearer_token(user)

  defp send_json(conn, method, path, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> dispatch(@endpoint, method, path, Jason.encode!(body))
  end
end

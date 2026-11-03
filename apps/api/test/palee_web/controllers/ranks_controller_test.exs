defmodule PaleeWeb.RanksControllerTest do
  @moduledoc """
  ADR-377: belts and levels. The box sets ladders, a coach promotes their
  clients, the person sees their own and their diplomas; another box sees
  nothing. ConnCase: real RLS.
  """

  use PaleeWeb.ConnCase, async: false

  import Palee.TestFixtures

  alias Palee.Organizations

  setup do
    owner = admin_fixture()
    {:ok, _} = Organizations.ensure_legacy_membership_for_migration(owner, :owner)
    member = user_fixture()
    {:ok, _} = Organizations.ensure_legacy_membership_for_migration(member, :member)
    other_member = user_fixture()
    {:ok, _} = Organizations.ensure_legacy_membership_for_migration(other_member, :member)
    slug = Organizations.legacy_organization_slug()

    %{
      owner: owner,
      member: member,
      other_member: other_member,
      admin: "/api/org/#{slug}/admin",
      staff: "/api/org/#{slug}/staff",
      me: "/api/org/#{slug}/me"
    }
  end

  test "a ladder from a template, promotions, stripes, withdrawal and diplomas",
       %{conn: conn} = ctx do
    assert %{"ladder" => %{"id" => ladder_id, "ranks" => [white, blue | _]} = ladder} =
             conn
             |> as(ctx.owner)
             |> send_json(:post, "#{ctx.admin}/rank-ladders", %{template: "bjj_adult"})
             |> json_response(201)

    assert ladder["discipline"] == "bjj_grappling"
    assert ladder["family"] == "combat"
    assert white["name"] == "Λευκή"

    assert %{"ladders" => [%{"id" => ^ladder_id}], "templates" => [_ | _]} =
             conn |> as(ctx.owner) |> get("#{ctx.admin}/rank-ladders") |> json_response(200)

    # A box member can't set ladders.
    assert conn |> as(ctx.member) |> get("#{ctx.admin}/rank-ladders") |> json_response(403)

    award = fn body ->
      conn
      |> as(ctx.owner)
      |> send_json(
        :post,
        "#{ctx.staff}/clients/#{ctx.member.id}/ranks",
        Map.put(body, :ladder_id, ladder_id)
      )
    end

    assert %{"award" => %{"rank_name" => "Λευκή", "certificate_number" => "R-" <> _}} =
             award.(%{rank_id: white["id"]}) |> json_response(201)

    assert %{"award" => %{"stripes" => 2}} =
             award.(%{rank_id: white["id"], stripes: 2}) |> json_response(201)

    assert %{"code" => "rank_not_above_current"} =
             award.(%{rank_id: white["id"], stripes: 1}) |> json_response(422)

    assert %{"code" => "too_many_stripes"} =
             award.(%{rank_id: white["id"], stripes: 5}) |> json_response(422)

    assert %{"award" => %{"id" => blue_award, "rank_name" => "Μπλε"}} =
             award.(%{rank_id: blue["id"], note: "Καλή δουλειά"}) |> json_response(201)

    assert %{"ladders" => [standing]} =
             conn |> as(ctx.member) |> get("#{ctx.me}/ranks") |> json_response(200)

    assert standing["current"]["rank"]["name"] == "Μπλε"
    assert standing["next"]["name"] == "Μωβ"
    assert %{"days" => %{"needed" => 730}, "ready" => false} = standing["progress"]
    assert length(standing["history"]) == 3

    # Diplomas: the person's own, and the coach's copy.
    pdf = conn |> as(ctx.member) |> get("#{ctx.me}/ranks/awards/#{blue_award}/certificate")
    assert response(pdf, 200) =~ "%PDF"
    assert ["application/pdf" <> _] = get_resp_header(pdf, "content-type")

    assert conn
           |> as(ctx.other_member)
           |> get("#{ctx.me}/ranks/awards/#{blue_award}/certificate")
           |> json_response(404)

    assert conn
           |> as(ctx.owner)
           |> get("#{ctx.staff}/rank-awards/#{blue_award}/certificate")
           |> response(200) =~ "%PDF"

    # Withdrawing falls back to the previous award; twice is refused.
    assert %{"award" => %{"revoked" => true}} =
             conn
             |> as(ctx.owner)
             |> send_json(:post, "#{ctx.staff}/rank-awards/#{blue_award}/revoke", %{
               reason: "Λάθος καταχώρηση"
             })
             |> json_response(200)

    assert %{"code" => "award_already_revoked"} =
             conn
             |> as(ctx.owner)
             |> send_json(:post, "#{ctx.staff}/rank-awards/#{blue_award}/revoke", %{
               reason: "Ξανά"
             })
             |> json_response(409)

    assert %{"ladders" => [%{"current" => %{"rank" => %{"name" => "Λευκή"}, "stripes" => 2}}]} =
             conn
             |> as(ctx.owner)
             |> get("#{ctx.staff}/clients/#{ctx.member.id}/ranks")
             |> json_response(200)

    # A held rank can't be removed from the ladder.
    assert %{"code" => "rank_in_use"} =
             conn
             |> as(ctx.owner)
             |> send_json(:put, "#{ctx.admin}/rank-ladders/#{ladder_id}", %{
               name: "Ζώνες BJJ",
               discipline: "bjj_grappling",
               ranks: [%{id: blue["id"], name: "Μπλε", color: "blue"}]
             })
             |> json_response(409)

    # Renaming and reordering keeps ids.
    assert %{
             "ladder" => %{
               "ranks" => [%{"id" => white_id, "name" => "Άσπρη"}, %{"name" => "Μπλε"}]
             }
           } =
             conn
             |> as(ctx.owner)
             |> send_json(:put, "#{ctx.admin}/rank-ladders/#{ladder_id}", %{
               name: "Ζώνες BJJ",
               discipline: "bjj_grappling",
               ranks: [
                 %{id: white["id"], name: "Άσπρη", color: "white", max_stripes: 4},
                 %{id: blue["id"], name: "Μπλε", color: "blue", max_stripes: 4}
               ]
             })
             |> json_response(200)

    assert white_id == white["id"]

    assert conn
           |> as(ctx.owner)
           |> delete("#{ctx.admin}/rank-ladders/#{ladder_id}")
           |> response(204)

    assert %{"ladders" => []} =
             conn |> as(ctx.owner) |> get("#{ctx.admin}/rank-ladders") |> json_response(200)
  end

  test "templates in the box's language, a coach's own copy and skills ticked one by one",
       %{conn: conn} = ctx do
    # ADR-400: the catalogue in English, with where its levels come from.
    assert %{"templates" => templates} =
             conn
             |> as(ctx.owner)
             |> get("#{ctx.admin}/rank-ladders?locale=en")
             |> json_response(200)

    assert length(templates) >= 70
    judo = Enum.find(templates, &(&1["key"] == "judo_kyu"))
    assert %{"name" => "Judo belts", "family" => "combat", "source" => "federation"} = judo
    assert %{"source" => "palee"} = Enum.find(templates, &(&1["key"] == "salsa_levels"))

    assert %{"templates" => greek} =
             conn |> as(ctx.owner) |> get("#{ctx.admin}/rank-ladders") |> json_response(200)

    assert Enum.find(greek, &(&1["key"] == "judo_kyu"))["name"] == "Ζώνες τζούντο"

    # A coach (not only the owner) starts a ladder and makes it their own.
    coach = user_fixture()
    {:ok, _} = Organizations.ensure_legacy_membership_for_migration(coach, :coach)

    assert %{"ladder" => %{"id" => ladder_id, "ranks" => [white, yellow | _]} = ladder} =
             conn
             |> as(coach)
             |> send_json(:post, "#{ctx.admin}/rank-ladders", %{
               template: "judo_kyu",
               locale: "en",
               name: "Kids judo"
             })
             |> json_response(201)

    assert ladder["name"] == "Kids judo"
    assert ladder["discipline"] == "judo"
    assert white["name"] == "White"
    assert [first_skill | _] = yellow["requirements"]["skills"]

    # Staff with full coaching scope tick one skill of the next rank; the client sees it.

    tick = fn user, body ->
      conn
      |> as(user)
      |> send_json(:put, "#{ctx.staff}/clients/#{ctx.member.id}/ranks/skills", body)
    end

    assert %{"ladders" => [standing]} =
             tick.(ctx.owner, %{rank_id: white["id"], skill: "Bow (rei) and judogi care"})
             |> json_response(200)

    assert [%{"skill" => "Bow (rei) and judogi care"}] = standing["progress"]["skills_checked"]
    refute standing["progress"]["all_skills_checked"]

    assert %{"code" => "unknown_skills"} =
             tick.(ctx.owner, %{rank_id: white["id"], skill: "Not on the list"})
             |> json_response(422)

    assert %{"ladders" => [mine]} =
             conn |> as(ctx.member) |> get("#{ctx.me}/ranks") |> json_response(200)

    assert [%{"skill" => "Bow (rei) and judogi care"}] = mine["progress"]["skills_checked"]

    assert %{"ladders" => [unticked]} =
             tick.(ctx.owner, %{
               rank_id: white["id"],
               skill: "Bow (rei) and judogi care",
               checked: false
             })
             |> json_response(200)

    assert unticked["progress"]["skills_checked"] == []

    # A box member can't tick skills.
    assert tick.(ctx.other_member, %{rank_id: yellow["id"], skill: first_skill})
           |> json_response(403)

    assert ladder_id
  end

  test "invalid ladders and another box's view", %{conn: conn} = ctx do
    assert %{"errors" => [%{"source" => %{"pointer" => "/ranks/0/color"}}]} =
             conn
             |> as(ctx.owner)
             |> send_json(:post, "#{ctx.admin}/rank-ladders", %{
               name: "X",
               discipline: "bjj_grappling",
               ranks: [%{name: "A", color: "teal"}]
             })
             |> json_response(422)

    conn
    |> as(ctx.owner)
    |> send_json(:post, "#{ctx.admin}/rank-ladders", %{template: "gymnastics_levels"})
    |> json_response(201)

    # The owner of another box sees none of this box's ladders.
    other_owner = admin_fixture()
    {:ok, other_box} = Organizations.create_organization(%{name: "Other Dojo"})

    {:ok, _} =
      Organizations.add_membership(%{
        organization_id: other_box.id,
        user_id: other_owner.id,
        role: :owner,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    assert %{"ladders" => []} =
             conn
             |> as(other_owner)
             |> get("/api/org/#{other_box.slug}/admin/rank-ladders")
             |> json_response(200)
  end

  defp as(conn, user), do: conn |> recycle() |> put_bearer_token(user)

  defp send_json(conn, method, path, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> dispatch(@endpoint, method, path, Jason.encode!(body))
  end
end

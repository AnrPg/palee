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

    # ADR-400 follow-up: a coach of their own clients doesn't keep ladders;
    # a head coach (every client) does, like the owner and admins.
    coach = user_fixture()
    {:ok, _} = Organizations.ensure_legacy_membership_for_migration(coach, :coach)

    assert conn
           |> as(coach)
           |> send_json(:post, "#{ctx.admin}/rank-ladders", %{template: "judo_kyu"})
           |> json_response(403)

    assert conn |> as(coach) |> get("#{ctx.admin}/rank-ladders") |> json_response(403)
    head_coach = head_coach_fixture()

    assert %{"ladder" => %{"id" => ladder_id, "ranks" => [white, yellow | _]} = ladder} =
             conn
             |> as(head_coach)
             |> send_json(:post, "#{ctx.admin}/rank-ladders", %{
               template: "judo_kyu",
               locale: "en",
               name: "Kids judo"
             })
             |> json_response(201)

    assert ladder["name"] == "Kids judo"
    # The template's default for «ready»: judo states intervals and skills.
    assert "skills" in ladder["ready_criteria"]
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

  test "skill ids keep ticks through renames; a class, a promotion and the ready list",
       %{conn: conn} = ctx do
    assert %{"box_disciplines" => []} =
             conn |> as(ctx.owner) |> get("#{ctx.admin}/rank-ladders") |> json_response(200)

    assert %{"ladder" => %{"id" => ladder_id, "ranks" => [white, blue]} = ladder} =
             conn
             |> as(ctx.owner)
             |> send_json(:post, "#{ctx.admin}/rank-ladders", %{
               name: "Kids BJJ",
               discipline: "bjj_grappling",
               ready_criteria: ["skills"],
               ranks: [
                 %{name: "White", color: "white"},
                 %{
                   name: "Blue",
                   color: "blue",
                   requirements: %{
                     min_days: 365,
                     skills: ["Armbar", "Triangle"],
                     skill_notes: ["Both sides", nil],
                     skill_videos: [nil, "https://video.example/triangle"]
                   }
                 }
               ]
             })
             |> json_response(201)

    assert ladder["ready_criteria"] == ["skills"]
    assert [armbar_id, triangle_id] = blue["requirements"]["skill_ids"]
    assert blue["requirements"]["skill_notes"] == ["Both sides", nil]

    # «at least one criterion»
    assert %{"errors" => [%{"source" => %{"pointer" => "/ready_criteria"}}]} =
             conn
             |> as(ctx.owner)
             |> send_json(:put, "#{ctx.admin}/rank-ladders/#{ladder_id}", %{
               name: "Kids BJJ",
               discipline: "bjj_grappling",
               ready_criteria: [],
               ranks: [%{id: white["id"], name: "White"}, %{id: blue["id"], name: "Blue"}]
             })
             |> json_response(422)

    award = fn user, body ->
      conn
      |> as(ctx.owner)
      |> send_json(
        :post,
        "#{ctx.staff}/clients/#{user.id}/ranks",
        Map.put(body, :ladder_id, ladder_id)
      )
      |> json_response(201)
    end

    award.(ctx.member, %{rank_id: white["id"]})
    award.(ctx.other_member, %{rank_id: white["id"]})

    # Mockup 3B: a class view and one skill for several people.
    assert %{"ladders" => [_], "people" => people} =
             conn
             |> as(ctx.owner)
             |> get(
               "#{ctx.staff}/ranks/skills/batch?user_ids=#{ctx.member.id},#{ctx.other_member.id}"
             )
             |> json_response(200)

    assert Enum.all?(people, &(&1["next_rank_ids"] == [blue["id"]] and &1["reachable"]))

    assert %{"updated" => updated, "skipped" => []} =
             conn
             |> as(ctx.owner)
             |> send_json(:put, "#{ctx.staff}/ranks/skills/batch", %{
               rank_id: blue["id"],
               skill_id: armbar_id,
               user_ids: [ctx.member.id, ctx.other_member.id]
             })
             |> json_response(200)

    assert Enum.sort(updated) == Enum.sort([ctx.member.id, ctx.other_member.id])

    # Someone who doesn't work towards that rank (no rank yet: White is next) is skipped.
    assert %{"updated" => [], "skipped" => [%{"reason" => "other_rank"}]} =
             conn
             |> as(ctx.owner)
             |> send_json(:put, "#{ctx.staff}/ranks/skills/batch", %{
               rank_id: blue["id"],
               skill_id: triangle_id,
               user_ids: [ctx.owner.id]
             })
             |> json_response(200)

    assert %{"code" => "unknown_skills"} =
             conn
             |> as(ctx.owner)
             |> send_json(:put, "#{ctx.staff}/ranks/skills/batch", %{
               rank_id: white["id"],
               skill: "Nothing",
               user_ids: [ctx.member.id]
             })
             |> json_response(422)

    # A coach of their own clients reaches nobody here.
    coach = user_fixture()
    {:ok, _} = Organizations.ensure_legacy_membership_for_migration(coach, :coach)

    assert %{"updated" => [], "skipped" => [%{"reason" => "not_your_client"}]} =
             conn
             |> as(coach)
             |> send_json(:put, "#{ctx.staff}/ranks/skills/batch", %{
               rank_id: blue["id"],
               skill_id: triangle_id,
               user_ids: [ctx.member.id]
             })
             |> json_response(200)

    # Renaming and reordering the skills keeps the tick.
    conn
    |> as(ctx.owner)
    |> send_json(:put, "#{ctx.admin}/rank-ladders/#{ladder_id}", %{
      name: "Kids BJJ",
      discipline: "bjj_grappling",
      ranks: [
        %{id: white["id"], name: "White", color: "white"},
        %{
          id: blue["id"],
          name: "Blue",
          color: "blue",
          requirements: %{
            min_days: 365,
            skills: ["Triangle", "Armbar from guard"],
            skill_ids: [triangle_id, armbar_id]
          }
        }
      ]
    })
    |> json_response(200)

    standing = fn ->
      conn
      |> as(ctx.member)
      |> get("#{ctx.me}/ranks")
      |> json_response(200)
      |> Map.fetch!("ladders")
      |> hd()
    end

    progress = standing.()["progress"]

    assert [%{"skill" => "Armbar from guard", "skill_id" => ^armbar_id}] =
             progress["skills_checked"]

    assert progress["criteria"] == ["skills"]
    refute progress["ready"]

    # The second tick, from the client's profile by id: ready counts skills only.
    conn
    |> as(ctx.owner)
    |> send_json(:put, "#{ctx.staff}/clients/#{ctx.member.id}/ranks/skills", %{
      rank_id: blue["id"],
      skill_id: triangle_id,
      checked_on: "2026-01-01",
      note: "Clean"
    })
    |> json_response(200)

    assert %{"ready" => true, "all_skills_checked" => true} = standing.()["progress"]

    # «Πληροί τις προϋποθέσεις»: the member, not the other one (one skill short).
    assert %{"people" => [%{"user_id" => ready_id, "next" => %{"name" => "Blue"}}]} =
             conn |> as(ctx.owner) |> get("#{ctx.staff}/ranks/ready") |> json_response(200)

    assert ready_id == ctx.member.id

    assert %{"people" => []} =
             conn |> as(coach) |> get("#{ctx.staff}/ranks/ready") |> json_response(200)

    assert conn |> as(ctx.member) |> get("#{ctx.staff}/ranks/ready") |> json_response(403)

    # Mockup 3C: a promotion ticks the skills ticked on the sheet.
    award.(ctx.other_member, %{
      rank_id: blue["id"],
      skills_checked: ["Triangle", "Armbar from guard"]
    })

    checks =
      Palee.Ranks.with_context(%{organization_id: legacy_organization_id()}, fn ->
        Palee.Ranks.list_skill_checks(ctx.other_member.id)
      end)

    assert checks |> Enum.map(& &1.skill_id) |> Enum.sort() == Enum.sort([armbar_id, triangle_id])
    # The armbar tick of the class keeps its date; the promotion's is told by the promotion.
    assert Enum.find(checks, &(&1.skill_id == triangle_id)).notified_at
  end

  test "new ticks are told once, grouped; undone ticks are never told", %{conn: conn} = ctx do
    %{"ladder" => %{"ranks" => [_white, blue]}} =
      conn
      |> as(ctx.owner)
      |> send_json(:post, "#{ctx.admin}/rank-ladders", %{
        name: "Judo",
        discipline: "judo",
        ranks: [
          %{name: "White"},
          %{name: "Yellow", requirements: %{skills: ["Ukemi", "O goshi", "Kesa gatame"]}}
        ]
      })
      |> json_response(201)

    tick = fn skill_id, checked ->
      conn
      |> as(ctx.owner)
      |> send_json(:put, "#{ctx.staff}/clients/#{ctx.member.id}/ranks/skills", %{
        rank_id: blue["id"],
        skill_id: skill_id,
        checked: checked
      })
      |> json_response(200)
    end

    [ukemi, o_goshi, kesa] = blue["requirements"]["skill_ids"]
    tick.(ukemi, true)
    tick.(o_goshi, true)
    tick.(kesa, true)
    tick.(kesa, false)

    context = %{organization_id: legacy_organization_id()}
    :ok = Palee.Application.RankSkillNotices.deliver(context, ctx.member.id)

    assert [%{payload: payload}] = rank_notices(ctx.member.id)
    assert payload["count"] in [2, "2"]
    assert payload["rank_name"] == "Yellow"

    # Told once: nothing new, nothing sent.
    :ok = Palee.Application.RankSkillNotices.deliver(context, ctx.member.id)
    assert length(rank_notices(ctx.member.id)) == 1

    # Ticked and undone inside the next window: nothing is sent.
    tick.(kesa, true)
    tick.(kesa, false)
    :ok = Palee.Application.RankSkillNotices.deliver(context, ctx.member.id)
    assert length(rank_notices(ctx.member.id)) == 1
  end

  test "classes attended since each person's date, counted at once" do
    organization_id = legacy_organization_id()
    a = user_fixture()
    b = user_fixture()
    class_type = class_type_fixture()

    for {user, at} <- [
          {a, ~U[2026-09-01 18:00:00Z]},
          {a, ~U[2026-03-01 18:00:00Z]},
          {b, ~U[2026-09-02 18:00:00Z]}
        ] do
      attend(organization_id, class_type.id, user.id, at)
    end

    context = %{organization_id: organization_id}

    counts =
      Palee.Scheduling.count_attended_since(context, %{a.id => ~D[2026-06-01], b.id => nil}, [])

    assert counts == %{a.id => 1, b.id => 1}

    assert counts ==
             Palee.Scheduling.count_attended_since(
               context,
               %{a.id => ~D[2026-06-01], b.id => nil},
               [class_type.id]
             )

    assert %{} ==
             Palee.Scheduling.count_attended_since(context, %{a.id => nil}, [Ecto.UUID.generate()])

    assert %{} == Palee.Scheduling.count_attended_since(context, %{}, [])
  end

  defp attend(organization_id, class_type_id, user_id, at) do
    class_id = Ecto.UUID.generate()
    at = at |> DateTime.to_naive()
    dump = &Ecto.UUID.dump!/1

    Palee.Repo.query!(
      """
      INSERT INTO scheduled_classes (id, organization_id, class_type_id, scheduled_at, capacity, inserted_at, updated_at)
      VALUES ($1, $2, $3, $4, 10, now(), now())
      """,
      [dump.(class_id), dump.(organization_id), dump.(class_type_id), at]
    )

    Palee.Repo.query!(
      """
      INSERT INTO bookings (id, organization_id, scheduled_class_id, user_id, status, inserted_at, updated_at)
      VALUES ($1, $2, $3, $4, 'approved', now(), now())
      """,
      [dump.(Ecto.UUID.generate()), dump.(organization_id), dump.(class_id), dump.(user_id)]
    )

    Palee.Repo.query!(
      """
      INSERT INTO class_attendance_records (id, organization_id, scheduled_class_id, user_id, status, marked_at, inserted_at, updated_at)
      VALUES ($1, $2, $3, $4, 'attended', $5, now(), now())
      """,
      [dump.(Ecto.UUID.generate()), dump.(organization_id), dump.(class_id), dump.(user_id), at]
    )
  end

  defp rank_notices(user_id) do
    user_id
    |> Palee.Notifications.list_for_user()
    |> Enum.filter(&(to_string(&1.type) == "rank_skills_checked"))
  end

  defp legacy_organization_id do
    {:ok, organization} = Organizations.ensure_legacy_organization_for_migration()
    organization.id
  end

  defp head_coach_fixture do
    coach = user_fixture()
    {:ok, membership} = Organizations.ensure_legacy_membership_for_migration(coach, :coach)

    {:ok, _} =
      Palee.Organizations.OrganizationStore.update_membership_settings(
        legacy_organization_id(),
        membership.id,
        %{coach_scope: :all}
      )

    coach
  end

  defp as(conn, user), do: conn |> recycle() |> put_bearer_token(user)

  defp send_json(conn, method, path, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> dispatch(@endpoint, method, path, Jason.encode!(body))
  end
end

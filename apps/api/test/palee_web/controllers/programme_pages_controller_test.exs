defmodule PaleeWeb.ProgrammePagesControllerTest do
  @moduledoc """
  ADR-540..544 end to end: the buyer's days («Έμεινε πίσω»: «Κάν' τη
  σήμερα», «Παράλειψη») with their assigned workouts moving along, the
  cover photo, equipment and minutes per session, what a draft lacks, and
  the «Προγράμματα» section of the box website.
  """
  use PaleeWeb.ConnCase, async: false

  import Ecto.Query
  import Palee.TestFixtures
  import Palee.TestSupport.ImageFixtures

  alias Palee.{AnalyticsHelpers, Media, Organizations, Repo}
  alias Palee.Application.{PublishBoxPublicProfile, UpdateBoxPublicProfile}
  alias Palee.Infrastructure.Tenancy.RepoContext
  alias Palee.TestSupport.MemoryObjectStore

  setup %{conn: conn} do
    MemoryObjectStore.start()
    owner = admin_fixture(%{nickname: "pages_owner"})
    buyer = user_fixture(%{role: :member, nickname: "pages_buyer"})
    stranger = user_fixture(%{role: :member, nickname: "pages_stranger"})

    {:ok, organization} =
      Organizations.create_organization(%{
        name: "Pages Box #{System.unique_integer([:positive])}"
      })

    AnalyticsHelpers.add_membership(organization, owner, :owner)
    AnalyticsHelpers.add_membership(organization, buyer, :member)
    AnalyticsHelpers.add_membership(organization, stranger, :member)
    {:ok, context} = Organizations.resolve_tenant_context(owner, organization.slug)

    strength =
      workout_fixture(owner, %{
        tenant_context: context,
        title: "Strength",
        type: :strength,
        estimated_duration_seconds: 2_700,
        sections: [
          %{
            name: "Main",
            order: 1,
            scoreable: false,
            exercises: [
              %{name: "Back Squat", order: 1, sets: 5},
              %{name: "Box Jumps", order: 2, sets: 3}
            ]
          }
        ]
      })

    engine =
      workout_fixture(owner, %{
        tenant_context: context,
        title: "Engine",
        estimated_duration_seconds: 1_200,
        sections: [
          %{
            name: "Main",
            order: 1,
            scoreable: false,
            exercises: [%{name: "Row", order: 1}, %{name: "Box Jumps", order: 2}]
          }
        ]
      })

    %{
      owner: owner,
      buyer: buyer,
      stranger: stranger,
      organization: organization,
      context: context,
      strength: strength,
      engine: engine,
      as: fn user -> put_bearer_token(conn, user) end,
      admin: "/api/org/#{organization.slug}/admin",
      me: "/api/org/#{organization.slug}/me"
    }
  end

  defp draft(ctx, attrs \\ %{}) do
    ctx.as.(ctx.owner)
    |> post(
      ctx.admin <> "/programmes",
      Map.merge(
        %{
          title: "Strength 2 weeks",
          summary: "Two weeks of strength",
          price_cents: 3_900,
          listing: "marketplace",
          draft_weeks: 2,
          draft_days: [
            %{day: 0, workout_id: ctx.strength.id},
            %{day: 2, workout_id: ctx.engine.id},
            %{day: 9, workout_id: ctx.strength.id}
          ]
        },
        attrs
      )
    )
    |> json_response(201)
    |> Map.fetch!("programme")
  end

  defp publish(ctx, programme) do
    ctx.as.(ctx.owner)
    |> post(ctx.admin <> "/programmes/#{programme["id"]}/publish", %{})
    |> json_response(200)
    |> Map.fetch!("programme")
  end

  defp buy(ctx, programme) do
    ctx.as.(ctx.owner)
    |> put(ctx.admin <> "/payments/account", %{provider: "sandbox", environment: "test"})
    |> json_response(200)

    result =
      ctx.as.(ctx.buyer)
      |> post(ctx.me <> "/programmes/#{programme["id"]}/buy", %{
        idempotency_key: "pages-buy-#{System.unique_integer([:positive])}",
        start_now: true,
        language: "el"
      })
      |> json_response(200)

    ref = URI.decode_query(URI.parse(result["payment"]["redirect_url"]).query)["sandbox_checkout"]

    ctx.as.(ctx.buyer)
    |> post(ctx.me <> "/payments/sandbox/complete", %{provider_ref: ref, outcome: "succeeded"})
    |> json_response(200)

    result["purchase_id"]
  end

  # The purchase started `days` days ago: its dates, deliveries and the
  # buyer's assigned-workout dates all move back.
  defp started_ago(ctx, purchase_id, days) do
    RepoContext.run(ctx.context, fn ->
      id = Ecto.UUID.dump!(purchase_id)

      Repo.query!(
        """
        UPDATE programme_purchases
        SET starts_on = starts_on - $2::int, ends_on = ends_on - $2::int,
            planned_ends_on = planned_ends_on - $2::int
        WHERE id = $1
        """,
        [id, days]
      )

      Repo.query!(
        """
        UPDATE assigned_workout_athletes l SET scheduled_for = l.scheduled_for - $2::int
        FROM programme_deliveries d
        WHERE d.purchase_id = $1 AND l.assigned_workout_id = d.assigned_workout_id
          AND l.athlete_id = d.user_id
        """,
        [id, days]
      )

      Repo.query!(
        "UPDATE programme_deliveries SET scheduled_for = scheduled_for - $2::int WHERE purchase_id = $1",
        [id, days]
      )
    end)
  end

  defp link_dates(ctx, purchase_id) do
    RepoContext.run(ctx.context, fn ->
      Repo.all(
        from d in "programme_deliveries",
          join: l in "assigned_workout_athletes",
          on: l.assigned_workout_id == d.assigned_workout_id and l.athlete_id == d.user_id,
          where: d.purchase_id == type(^purchase_id, :binary_id),
          select: {d.day, d.scheduled_for, l.scheduled_for}
      )
    end)
    |> Enum.sort()
  end

  defp upload_cover(ctx, width, height) do
    body = jpeg(width, height)

    %{"media_id" => id} =
      ctx.as.(ctx.owner)
      |> post(ctx.admin <> "/programme-covers", %{
        content_type: "image/jpeg",
        byte_size: byte_size(body)
      })
      |> json_response(200)

    media = Media.get(%{organization_id: ctx.organization.id}, :tenant, id)
    :ok = MemoryObjectStore.put_object(:media_public, media.object_key, body, "image/jpeg")

    assert %{"media" => %{"status" => "ready"}} =
             ctx.as.(ctx.owner)
             |> post(ctx.admin <> "/programme-covers/#{id}/complete", %{})
             |> json_response(200)

    id
  end

  describe "the buyer's days (ADR-540)" do
    test "a missed day is behind; skip it or do it today and the rest follows", ctx do
      purchase_id = ctx |> draft() |> then(&publish(ctx, &1)) |> then(&buy(ctx, &1))
      started_ago(ctx, purchase_id, 3)
      path = ctx.me <> "/programme-purchases/#{purchase_id}/days"

      days = ctx.as.(ctx.buyer) |> get(path) |> json_response(200)
      today = Date.from_iso8601!(days["today"])

      assert days["progress"] == %{
               "total" => 3,
               "done" => 0,
               "skipped" => 0,
               "behind" => 2,
               "remaining" => 3
             }

      assert %{"day" => 0, "can_do_today" => true, "can_skip" => true} = days["behind"]
      assert length(days["days"]) == 14
      assert Enum.at(days["days"], 1)["status"] == "rest"

      assert [%{"assigned_workout_id" => assigned, "done" => false, "title" => "Strength"}] =
               Enum.at(days["days"], 0)["workouts"]

      assert is_binary(assigned)

      # Someone else never reaches it.
      ctx.as.(ctx.stranger) |> get(path) |> json_response(404)

      ctx.as.(ctx.stranger)
      |> post(path <> "/skip", %{day: 0})
      |> json_response(404)

      # «Παράλειψη» on day 0: nothing moves.
      skipped = ctx.as.(ctx.buyer) |> post(path <> "/skip", %{day: 0}) |> json_response(200)
      assert Enum.at(skipped["days"], 0)["status"] == "skipped"
      assert skipped["behind"]["day"] == 2
      assert skipped["ends_on"] == days["ends_on"]

      # Only a behind day can be moved.
      ctx.as.(ctx.buyer)
      |> post(path <> "/do-today", %{day: 9})
      |> json_response(409)
      |> then(&assert(&1["code"] == "programme_day_not_behind"))

      ctx.as.(ctx.buyer)
      |> post(path <> "/do-today", %{day: 1})
      |> json_response(404)

      # «Κάν' τη σήμερα» on day 2 (yesterday): day 2 today, day 9 a day later.
      moved = ctx.as.(ctx.buyer) |> post(path <> "/do-today", %{day: 2}) |> json_response(200)
      assert Enum.at(moved["days"], 2)["status"] == "today"
      assert Enum.at(moved["days"], 2)["date"] == Date.to_iso8601(today)
      assert Enum.at(moved["days"], 9)["date"] == Date.to_iso8601(Date.add(today, 7))
      assert moved["behind"] == nil
      assert moved["ends_on"] == Date.to_iso8601(Date.add(Date.from_iso8601!(days["ends_on"]), 1))
      assert moved["planned_ends_on"] == days["ends_on"]

      # The assigned workouts moved with their days (and the deliveries too).
      assert [
               {0, d0, l0},
               {2, ^today, ^today},
               {9, d9, d9}
             ] = link_dates(ctx, purchase_id)

      assert d0 == l0 and d0 == Date.add(today, -3)
      assert d9 == Date.add(today, 7)

      # The purchase shows the moved dates.
      purchase =
        ctx.as.(ctx.buyer)
        |> get(ctx.me <> "/programme-purchases/#{purchase_id}")
        |> json_response(200)

      assert Enum.find(purchase["purchase"]["days"], &(&1["day"] == 2))["date"] ==
               Date.to_iso8601(today)
    end

    test "a day whose WOD the buyer logged is done and counts in the progress", ctx do
      purchase_id = ctx |> draft() |> then(&publish(ctx, &1)) |> then(&buy(ctx, &1))
      started_ago(ctx, purchase_id, 3)
      path = ctx.me <> "/programme-purchases/#{purchase_id}/days"
      days = ctx.as.(ctx.buyer) |> get(path) |> json_response(200)
      [%{"assigned_workout_id" => assigned}] = Enum.at(days["days"], 0)["workouts"]

      {:ok, buyer_context} =
        Organizations.resolve_tenant_context(ctx.buyer, ctx.organization.slug)

      assert {:ok, _entry, :created} =
               Palee.Application.LogTrainingEntry.call(buyer_context, ctx.buyer, %{
                 "source_type" => "assigned_workout",
                 "source_reference_id" => assigned,
                 "performed_at" =>
                   DateTime.to_iso8601(DateTime.add(DateTime.utc_now(), -1, :day)),
                 "idempotency_key" => "log-#{System.unique_integer([:positive])}"
               })

      days = ctx.as.(ctx.buyer) |> get(path) |> json_response(200)
      assert %{"status" => "done", "workouts" => [%{"done" => true}]} = Enum.at(days["days"], 0)
      assert %{"done" => 1, "behind" => 1, "remaining" => 2} = days["progress"]
      assert days["behind"]["day"] == 2

      # A done day is neither moved nor skipped.
      ctx.as.(ctx.buyer) |> post(path <> "/skip", %{day: 0}) |> json_response(409)
    end

    test "too long away: moving is refused within the cap, skipping still works", ctx do
      purchase_id = ctx |> draft() |> then(&publish(ctx, &1)) |> then(&buy(ctx, &1))
      started_ago(ctx, purchase_id, 30)
      path = ctx.me <> "/programme-purchases/#{purchase_id}/days"

      days = ctx.as.(ctx.buyer) |> get(path) |> json_response(200)
      assert %{"day" => 0, "can_do_today" => false} = days["behind"]

      ctx.as.(ctx.buyer)
      |> post(path <> "/do-today", %{day: 0})
      |> json_response(409)
      |> then(&assert(&1["code"] == "programme_schedule_limit"))

      ctx.as.(ctx.buyer) |> post(path <> "/skip", %{day: 0}) |> json_response(200)
    end
  end

  describe "the editor (ADR-542, ADR-544)" do
    test "equipment and minutes come from the WODs; the author's choice wins", ctx do
      programme =
        draft(ctx, %{summary: nil, draft_days: [%{day: 0, workout_id: ctx.strength.id}]})

      shown =
        ctx.as.(ctx.owner)
        |> get(ctx.admin <> "/programmes/#{programme["id"]}")
        |> json_response(200)
        |> Map.fetch!("programme")

      assert shown["facts"] == %{"equipment" => ["barbell", "box"], "minutes_per_session" => 45}
      assert shown["main_equipment"] == ["barbell", "box"]
      assert shown["minutes_per_session"] == 45

      assert [
               %{"key" => "empty_weeks", "blocking" => false, "weeks" => [2]},
               %{"key" => "summary", "blocking" => false}
             ] = shown["readiness"]

      updated =
        ctx.as.(ctx.owner)
        |> patch(ctx.admin <> "/programmes/#{programme["id"]}", %{
          equipment: ["rings"],
          equipment_removed: ["box"],
          draft_days: [
            %{day: 0, workout_id: ctx.strength.id},
            %{day: 1, workout_id: ctx.engine.id},
            %{day: 8, workout_id: ctx.engine.id}
          ]
        })
        |> json_response(200)
        |> Map.fetch!("programme")

      assert updated["facts"]["equipment"] == ["box", "rower", "barbell"]
      assert updated["main_equipment"] == ["rings", "rower", "barbell"]
      # (45 + 20 + 20) / 3 = 28.3 → 30.
      assert updated["minutes_per_session"] == 30
      assert [%{"key" => "summary"}] = updated["readiness"]

      ctx.as.(ctx.owner)
      |> patch(ctx.admin <> "/programmes/#{programme["id"]}", %{equipment: ["kettlebells"]})
      |> json_response(422)

      # The page shows what was frozen at publication, with the author's choice.
      published = publish(ctx, programme)
      assert published["version"]["number"] == 1

      public =
        build_conn()
        |> get("/api/public/boxes/#{ctx.organization.slug}/programmes/#{programme["id"]}")

      # The box page is not published: nothing public yet.
      assert public.status == 404
      publish_page(ctx)

      public =
        build_conn()
        |> get("/api/public/boxes/#{ctx.organization.slug}/programmes/#{programme["id"]}")
        |> json_response(200)
        |> Map.fetch!("programme")

      assert public["main_equipment"] == ["rings", "rower", "barbell"]
      assert public["minutes_per_session"] == 30
      assert public["cover_url"] == nil

      catalogue = build_conn() |> get("/api/public/programmes") |> json_response(200)
      row = Enum.find(catalogue["programmes"], &(&1["id"] == programme["id"]))
      assert row["main_equipment"] == ["rings", "rower", "barbell"]
      assert row["minutes_per_session"] == 30
      refute Map.has_key?(row, "facts")
    end

    test "the public page outlines every day without its WOD, and names the coach", ctx do
      bare = workout_fixture(ctx.owner, %{tenant_context: ctx.context, title: "Bare"})

      programme =
        draft(ctx, %{
          preview_days: 1,
          draft_days: [
            %{day: 0, workout_id: ctx.strength.id},
            %{day: 2, workout_id: ctx.engine.id},
            %{day: 2, workout_id: ctx.strength.id},
            %{day: 9, workout_id: bare.id}
          ]
        })

      publish(ctx, programme)
      publish_page(ctx)
      path = "/api/public/boxes/#{ctx.organization.slug}/programmes/#{programme["id"]}"
      public = build_conn() |> get(path) |> json_response(200) |> Map.fetch!("programme")

      assert public["coach_name"] == "pages_owner"
      assert [%{"day" => 0, "title" => "Strength"}] = public["preview"]

      assert [%{"week" => 1, "sessions" => 3, "days" => week1}, %{"week" => 2, "days" => week2}] =
               public["week_outline"]

      assert length(week1) == 7 and length(week2) == 7

      assert Enum.at(week1, 0) == %{
               "day" => 0,
               "weekday" => 0,
               "rest" => false,
               "workout_type" => "strength",
               "minutes" => 45,
               "preview" => true
             }

      assert %{"rest" => true, "workout_type" => nil, "minutes" => nil, "preview" => false} =
               Enum.at(week1, 1)

      # Two WODs that day: the longer one's type, 20 + 45 minutes.
      assert %{"day" => 2, "rest" => false, "workout_type" => "strength", "minutes" => 65} =
               Enum.at(week1, 2)

      # A WOD without a duration: the type only.
      assert %{"day" => 9, "weekday" => 2, "workout_type" => "crossfit", "minutes" => nil} =
               Enum.at(week2, 2)

      # Locked days never carry a WOD.
      for day <- week1 ++ week2 do
        refute Map.has_key?(day, "title") or Map.has_key?(day, "workout_id")
      end

      Repo.query!("UPDATE users SET nickname = $2, display_nickname = $3 WHERE id = $1", [
        Ecto.UUID.dump!(ctx.owner.id),
        "deleted.0123456789",
        "Deleted account"
      ])

      public = build_conn() |> get(path) |> json_response(200) |> Map.fetch!("programme")
      assert public["coach_name"] == nil
    end

    test "a WOD without a duration leaves the minutes out", ctx do
      bare = workout_fixture(ctx.owner, %{tenant_context: ctx.context, title: "Bare"})

      programme =
        draft(ctx, %{
          draft_days: [%{day: 0, workout_id: ctx.strength.id}, %{day: 1, workout_id: bare.id}]
        })

      shown =
        ctx.as.(ctx.owner)
        |> get(ctx.admin <> "/programmes/#{programme["id"]}")
        |> json_response(200)
        |> Map.fetch!("programme")

      assert shown["minutes_per_session"] == nil
      # Air squats need nothing, but the barbell and box are there.
      assert shown["main_equipment"] == ["barbell", "box"]
    end
  end

  describe "the cover (ADR-541)" do
    test "set from an original with its edit, shown publicly, replaced and removed", ctx do
      programme = ctx |> draft() |> then(&publish(ctx, &1))
      publish_page(ctx)
      original = upload_cover(ctx, 1_200, 1_600)
      rendered = upload_cover(ctx, 1_600, 900)
      path = ctx.admin <> "/programmes/#{programme["id"]}/cover"

      edit = %{
        rotation: 90,
        zoom: 1.2,
        brightness: 1.1,
        crop: %{x: 0, y: 0.1, width: 1, height: 0.75}
      }

      # A square is not a cover.
      square = upload_cover(ctx, 1_000, 1_000)

      ctx.as.(ctx.owner)
      |> put(path, %{media_id: square})
      |> json_response(422)
      |> then(&assert(&1["code"] == "invalid_cover_size"))

      ctx.as.(ctx.owner)
      |> put(path, %{
        media_id: rendered,
        original_media_id: original,
        edit: %{edit | rotation: 45}
      })
      |> json_response(422)

      # Members cannot set it.
      ctx.as.(ctx.buyer) |> put(path, %{media_id: rendered}) |> json_response(403)

      set =
        ctx.as.(ctx.owner)
        |> put(path, %{media_id: rendered, original_media_id: original, edit: edit})
        |> json_response(200)
        |> Map.fetch!("programme")

      assert %{
               "media_id" => ^rendered,
               "original_media_id" => ^original,
               "url" => url,
               "original_url" => original_url,
               "aspect" => "16:9",
               "edit" => %{"rotation" => 90, "zoom" => 1.2, "brightness" => 1.1}
             } = set["cover"]

      assert url =~ "https://media.test/media_public/"
      assert original_url != url
      assert set["cover_url"] == url
      assert Media.get(%{organization_id: ctx.organization.id}, :tenant, rendered).attached_at

      public =
        build_conn()
        |> get("/api/public/boxes/#{ctx.organization.slug}/programmes/#{programme["id"]}")
        |> json_response(200)

      assert public["programme"]["cover_url"] == url
      refute Map.has_key?(public["programme"], "cover")

      listed = build_conn() |> get("/api/public/programmes") |> json_response(200)
      assert Enum.find(listed["programmes"], &(&1["id"] == programme["id"]))["cover_url"] == url

      staff_list =
        ctx.as.(ctx.owner) |> get(ctx.admin <> "/programmes") |> json_response(200)

      assert hd(staff_list["programmes"])["cover_url"] == url

      # A new cover (no edit: the rendered one is its own original) replaces
      # both, and the old uploads go.
      again = upload_cover(ctx, 1_920, 1_080)

      replaced =
        ctx.as.(ctx.owner)
        |> put(path, %{media_id: again})
        |> json_response(200)
        |> Map.fetch!("programme")

      assert replaced["cover"]["original_media_id"] == again
      assert Media.get(%{organization_id: ctx.organization.id}, :tenant, rendered) == nil
      assert Media.get(%{organization_id: ctx.organization.id}, :tenant, original) == nil

      removed =
        ctx.as.(ctx.owner) |> delete(path) |> json_response(200) |> Map.fetch!("programme")

      assert removed["cover"] == nil
      assert removed["cover_url"] == nil
      assert Media.get(%{organization_id: ctx.organization.id}, :tenant, again) == nil
    end
  end

  describe "the box website (ADR-543)" do
    test "«Προγράμματα» shows only with a programme on sale, newest first, with the total",
         ctx do
      publish_page(ctx)
      site = "/api/public/sites/#{ctx.organization.slug}"

      empty = build_conn() |> get(site) |> json_response(200)
      refute "programmes" in empty["sections"]
      assert empty["programmes"] == []
      assert empty["programmes_total"] == 0

      for n <- 1..4, do: ctx |> draft(%{title: "Programme #{n}"}) |> then(&publish(ctx, &1))
      # A draft is not on sale.
      draft(ctx, %{title: "Not yet"})

      shown = build_conn() |> get(site) |> json_response(200)
      assert "programmes" in shown["sections"]
      assert shown["programmes_total"] == 4

      # The ADR-530 list (at most 6; the website shows the first three).
      assert [%{"title" => "Programme 4", "weeks" => 2, "cover_url" => nil} | _] =
               items = shown["programmes"]

      assert length(items) == 4

      # The owner hides it like any other section.
      settings =
        ctx.as.(ctx.owner)
        |> get(ctx.admin <> "/site")
        |> json_response(200)
        |> Map.fetch!("settings")

      assert "programmes" in settings["section_order"]

      ctx.as.(ctx.owner)
      |> put(ctx.admin <> "/site", %{
        section_order: settings["section_order"],
        hidden_sections: ["programmes"],
        lock_version: settings["lock_version"]
      })
      |> json_response(200)

      # ADR-530: a settings change goes live only with «Δημοσίευση».
      ctx.as.(ctx.owner) |> post(ctx.admin <> "/site/publish") |> json_response(200)

      hidden = build_conn() |> get(site) |> json_response(200)
      refute "programmes" in hidden["sections"]
      assert hidden["programmes"] == []
      assert hidden["programmes_total"] == 0
    end
  end

  defp publish_page(ctx) do
    {:ok, profile} =
      UpdateBoxPublicProfile.call(ctx.context, %{
        "about" => "A box that sells programmes",
        "disciplines" => ["crossfit"]
      })

    {:ok, _profile} =
      PublishBoxPublicProfile.publish(ctx.context, %{"lock_version" => profile.lock_version})
  end
end

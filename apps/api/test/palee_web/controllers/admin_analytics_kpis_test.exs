defmodule PaleeWeb.AdminAnalyticsKpisTest do
  @moduledoc """
  ADR-462 over HTTP: the period and filters of the staff summaries,
  previous-period deltas, k-anonymity of the opt-in demographics, the
  metric resets of a box (owner and admins only, audited, undoable, with a
  history) and a member's own Πρόοδος resets, which never touch the box.
  """

  use PaleeWeb.ConnCase, async: false

  import Ecto.Query
  import Palee.TestFixtures

  alias Palee.Execution.WorkoutExecution
  alias Palee.{Organizations, Repo, Scheduling}
  alias Palee.TimeZones.ZonedTime

  setup %{conn: conn} do
    {:ok, box} =
      Organizations.create_organization(%{name: "KPI Box #{System.unique_integer([:positive])}"})

    owner = user_fixture()
    add!(box, owner, [:owner])
    {:ok, context} = Organizations.resolve_tenant_context(owner, box.slug)

    zone = ZonedTime.default_zone()
    today = ZonedTime.local_date(DateTime.utc_now(), zone)
    beginner = class_type!(box, "Fundamentals", "beginner")
    advanced = class_type!(box, "Competitors", "advanced")

    members = for _ <- 1..7, do: member!(box)

    # Current period (30 days): a beginner class at 07:00 and an advanced
    # one at 18:00. Previous period: a beginner class at 07:00.
    morning = class!(box, beginner, Date.add(today, -3), ~T[07:00:00], zone)
    evening = class!(box, advanced, Date.add(today, -2), ~T[18:00:00], zone)
    earlier = class!(box, beginner, Date.add(today, -40), ~T[07:00:00], zone)

    Enum.each(Enum.take(members, 4), &attend!(box, morning, &1, "attended"))
    attend!(box, morning, Enum.at(members, 4), "no_show")
    Enum.each(Enum.slice(members, 5, 2), &attend!(box, evening, &1, "attended"))
    Enum.each(Enum.take(members, 3), &attend!(box, earlier, &1, "attended"))

    # Two members told the box their division: too few to show.
    Enum.each(Enum.take(members, 2), &opt_in!(box, &1, "women", 1990))

    %{
      conn: conn,
      box: box,
      owner: owner,
      context: context,
      members: members,
      beginner: beginner,
      advanced: advanced,
      morning: morning,
      today: today
    }
  end

  defp summary(ctx, params \\ %{}) do
    ctx.conn
    |> recycle()
    |> put_bearer_token(ctx.owner)
    |> get("/api/org/#{ctx.box.slug}/admin/analytics/summary", params)
    |> json_response(200)
  end

  defp kpi(body, key), do: Map.fetch!(body["kpis"], key)

  test "the period, previous-period deltas and every KPI key", ctx do
    body = summary(ctx, %{days: 30})

    assert body["period"]["days"] == 30
    assert body["period"]["to"] == Date.to_iso8601(ctx.today)
    assert body["period"]["previous_to"] == Date.to_iso8601(Date.add(ctx.today, -30))

    attended = kpi(body, "training.attendance_by_hour")
    assert attended["value"] == 6
    assert attended["previous"] == 3
    assert attended["delta"] == 3
    assert attended["since"] == nil
    assert Enum.find(attended["rows"], &(&1["key"] == 7))["count"] == 4
    assert Enum.find(attended["rows"], &(&1["key"] == 18))["count"] == 2

    assert kpi(body, "training.no_show_rate")["value"] == Float.round(100 / 7, 1)
    assert kpi(body, "overview.active_members")["value"] == 7
    assert is_map(body["execution"]["previous"])

    for key <- Palee.Analytics.metric_keys(:organization),
        not String.starts_with?(key, "finance.") do
      assert Map.has_key?(body["kpis"], key), "missing #{key}"
    end

    # «Κατανομή γεγονότων»: grouped by category.
    assert is_list(body["analytics"]["events"]["by_category"])

    # An explicit from/to wins over days.
    from = Date.to_iso8601(Date.add(ctx.today, -2))
    body = summary(ctx, %{from: from, to: Date.to_iso8601(ctx.today)})
    assert body["period"]["days"] == 3
    assert kpi(body, "training.attendance_by_hour")["value"] == 2
  end

  test "class filters: type, level, coach-free time of day", ctx do
    by_type = summary(ctx, %{class_type_ids: ctx.beginner.id})
    assert kpi(by_type, "training.attendance_by_hour")["value"] == 4
    assert kpi(by_type, "training.attendance_by_hour")["previous"] == 3
    assert by_type["filter"]["class_type_ids"] == [ctx.beginner.id]

    assert kpi(summary(ctx, %{levels: "advanced"}), "training.attendance_by_hour")["value"] == 2

    assert kpi(summary(ctx, %{time_of_day: "evening"}), "training.attendance_by_hour")["value"] ==
             2

    assert kpi(summary(ctx, %{time_of_day: "morning,midday"}), "training.attendance_by_hour")[
             "value"
           ] == 4

    assert %{"errors" => _} =
             ctx.conn
             |> recycle()
             |> put_bearer_token(ctx.owner)
             |> get("/api/org/#{ctx.box.slug}/admin/analytics/summary", %{levels: "expert"})
             |> json_response(422)
  end

  test "opt-in demographics are k-anonymous, unknown included", ctx do
    women = summary(ctx, %{genders: "women"})
    entry = kpi(women, "training.attendance_by_hour")
    assert entry["suppressed"] == true
    assert entry["value"] == nil
    assert entry["rows"] == []

    genders = kpi(women, "demographics.genders")["rows"]
    assert %{"key" => "women", "suppressed" => true} = Enum.find(genders, &(&1["key"] == "women"))
    refute Map.has_key?(Enum.find(genders, &(&1["key"] == "women")), "people")

    # The five who gave no division are a group of five: shown.
    unknown = summary(ctx, %{genders: "unknown"})
    refute kpi(unknown, "overview.active_members")["suppressed"]
    assert kpi(unknown, "overview.active_members")["value"] == 5

    assert %{"key" => "unknown", "people" => 5} =
             Enum.find(kpi(unknown, "demographics.genders")["rows"], &(&1["key"] == "unknown"))

    assert kpi(summary(ctx, %{age_bands: "35_44"}), "overview.active_members")["suppressed"]
  end

  test "an owner resets a box metric; it is audited, undoable and in the history", ctx do
    authed = fn -> ctx.conn |> recycle() |> put_bearer_token(ctx.owner) end
    base = "/api/org/#{ctx.box.slug}/admin/analytics"

    %{"reset" => reset} =
      authed.()
      |> post("#{base}/metrics/training.attendance_by_hour/reset")
      |> json_response(201)

    assert reset["metric_key"] == "training.attendance_by_hour"
    assert reset["scope"] == "organization"

    body = summary(ctx)
    attended = kpi(body, "training.attendance_by_hour")
    assert attended["value"] == 0
    assert attended["previous"] == nil
    assert is_binary(attended["since"])
    # Other metrics keep their own baseline.
    assert kpi(body, "training.no_show_rate")["since"] == nil

    assert audit_count(ctx.box, "analytics_metric_reset") == 1

    history = authed.() |> get("#{base}/resets") |> json_response(200)
    assert history["total"] == 1
    assert [%{"active" => true, "before" => %{"value" => 6}}] = history["entries"]

    %{"reset" => undone} =
      authed.() |> post("#{base}/resets/#{reset["id"]}/undo") |> json_response(200)

    assert undone["undone_by"] == ctx.owner.id
    assert audit_count(ctx.box, "analytics_metric_reset_undone") == 1
    assert kpi(summary(ctx), "training.attendance_by_hour")["value"] == 6

    assert %{"code" => "already_undone"} =
             authed.() |> post("#{base}/resets/#{reset["id"]}/undo") |> json_response(409)

    assert %{"code" => "metric_not_resettable"} =
             authed.()
             |> post("#{base}/metrics/overview.active_members/reset")
             |> json_response(422)

    assert %{"code" => "unknown_metric"} =
             authed.() |> post("#{base}/metrics/nope.nothing/reset") |> json_response(404)
  end

  test "only owners and admins may reset", ctx do
    coach = user_fixture()
    add!(ctx.box, coach, [:coach])
    desk = user_fixture()
    add!(ctx.box, desk, [:front_desk])

    for user <- [coach, desk] do
      assert ctx.conn
             |> recycle()
             |> put_bearer_token(user)
             |> post(
               "/api/org/#{ctx.box.slug}/admin/analytics/metrics/training.no_show_rate/reset"
             )
             |> response(403)
    end

    admin = user_fixture()
    add!(ctx.box, admin, [:admin])

    assert ctx.conn
           |> recycle()
           |> put_bearer_token(admin)
           |> post("/api/org/#{ctx.box.slug}/admin/analytics/metrics/training.no_show_rate/reset")
           |> response(201)
  end

  test "a member resets their own Πρόοδος, never the box's figures", ctx do
    member = hd(ctx.members)
    execution!(ctx, member)
    authed = fn -> ctx.conn |> recycle() |> put_bearer_token(member) end

    %{"progress" => before} = authed.() |> get("/api/me/progress") |> json_response(200)
    assert before["totals"]["sessions"] == 1

    %{"reset" => reset} =
      authed.() |> post("/api/me/progress/metrics/progress.totals/reset") |> json_response(201)

    assert reset["scope"] == "member"

    %{"progress" => progress} = authed.() |> get("/api/me/progress") |> json_response(200)
    assert progress["totals"]["sessions"] == 0
    assert Enum.sum(Enum.map(progress["weekly"], & &1["sessions"])) == 1
    assert Map.has_key?(progress["metric_baselines"], "progress.totals")

    depth = authed.() |> get("/api/me/progress/depth") |> json_response(200)
    assert depth["metric_baselines"]["progress.totals"]

    # The box sees nothing of it: no baseline, no audit event, same figures.
    box = summary(ctx)
    assert Enum.all?(Map.values(box["kpis"]), &is_nil(&1["since"]))
    assert audit_count(ctx.box, "analytics_metric_reset") == 0
    assert kpi(box, "training.attendance_by_hour")["value"] == 6

    staff =
      ctx.conn
      |> recycle()
      |> put_bearer_token(ctx.owner)
      |> get("/api/org/#{ctx.box.slug}/admin/analytics/resets")
      |> json_response(200)

    assert staff["total"] == 0

    assert %{"total" => 1, "entries" => [%{"metric_key" => "progress.totals"}]} =
             authed.() |> get("/api/me/progress/resets") |> json_response(200)

    # Another person cannot undo it; the member can.
    assert ctx.conn
           |> recycle()
           |> put_bearer_token(Enum.at(ctx.members, 1))
           |> post("/api/me/progress/resets/#{reset["id"]}/undo")
           |> response(404)

    assert authed.() |> post("/api/me/progress/resets/#{reset["id"]}/undo") |> response(200)
    %{"progress" => progress} = authed.() |> get("/api/me/progress") |> json_response(200)
    assert progress["totals"]["sessions"] == 1

    assert %{"code" => "unknown_metric"} =
             authed.()
             |> post("/api/me/progress/metrics/training.no_show_rate/reset")
             |> json_response(404)
  end

  test "the finance summary takes the same period and returns finance KPIs", ctx do
    body =
      ctx.conn
      |> put_bearer_token(ctx.owner)
      |> get("/api/org/#{ctx.box.slug}/admin/finance/summary", %{days: 7})
      |> json_response(200)

    assert body["period"]["days"] == 7

    for key <- Palee.Analytics.section_metric_keys(:finance) do
      assert Map.has_key?(body["kpis"], key)
    end

    assert is_integer(body["previous_totals"]["paid_revenue_cents"])
  end

  test "attendance and events snapshot the class's dimensions when written", ctx do
    member = Enum.at(ctx.members, 6)

    {:ok, _attendance} =
      Scheduling.record_attendance(ctx.context, %{
        scheduled_class_id: ctx.morning.id,
        user_id: member.id,
        status: "attended"
      })

    [row] =
      Repo.all(
        from(record in "class_attendance_records",
          where:
            record.scheduled_class_id == ^Ecto.UUID.dump!(ctx.morning.id) and
              record.user_id == ^Ecto.UUID.dump!(member.id),
          select: %{
            class_type_id: record.class_type_id,
            level: record.level,
            class_starts_at: record.class_starts_at
          }
        )
      )

    assert Ecto.UUID.load!(row.class_type_id) == ctx.beginner.id
    assert row.level == "beginner"
    assert row.class_starts_at

    Repo.query!("SELECT set_config('app.organization_id', $1, false)", [ctx.box.id])

    {:ok, event} =
      Palee.Analytics.record_event(%{
        event_name: "class_booking_requested",
        user_id: member.id,
        context_type: "class_booking",
        metadata: %{"scheduled_class_id" => ctx.morning.id}
      })

    [snapshot] =
      Repo.all(
        from(e in "analytics_events",
          where: e.id == ^Ecto.UUID.dump!(event.id),
          select: {e.class_type_id, e.level}
        )
      )

    assert {class_type_id, "beginner"} = snapshot
    assert Ecto.UUID.load!(class_type_id) == ctx.beginner.id
  end

  ## Fixtures

  defp add!(organization, user, roles) do
    {:ok, _membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: user.id,
        role: hd(roles),
        roles: roles,
        status: :active,
        joined_at: DateTime.add(DateTime.utc_now(), -400, :day)
      })
  end

  defp member!(box) do
    user = user_fixture()
    add!(box, user, [:member])
    now = DateTime.utc_now()

    insert!("memberships", %{
      organization_id: box.id,
      user_id: user.id,
      user_type_snapshot: "member",
      status: "active",
      signup_source: "admin_created",
      starts_on: Date.add(Date.utc_today(), -400),
      inserted_at: now,
      updated_at: now
    })

    user
  end

  defp class_type!(box, name, level) do
    now = DateTime.utc_now()
    id = Ecto.UUID.generate()

    insert!("class_types", %{
      id: id,
      organization_id: box.id,
      name: name,
      slug: "#{String.downcase(name)}-#{System.unique_integer([:positive])}",
      level: level,
      inserted_at: now,
      updated_at: now
    })

    %{id: id}
  end

  defp class!(box, type, date, time, zone) do
    now = DateTime.utc_now()
    id = Ecto.UUID.generate()

    insert!("scheduled_classes", %{
      id: id,
      organization_id: box.id,
      class_type_id: type.id,
      scheduled_at: ZonedTime.to_utc(date, time, zone),
      capacity: 10,
      inserted_at: now,
      updated_at: now
    })

    %{id: id}
  end

  defp attend!(box, class, user, status) do
    now = DateTime.utc_now()

    insert!("class_attendance_records", %{
      organization_id: box.id,
      scheduled_class_id: class.id,
      user_id: user.id,
      status: status,
      marked_at: now,
      inserted_at: now,
      updated_at: now
    })
  end

  defp opt_in!(box, user, division, birth_year) do
    insert!("leaderboard_opt_ins", %{
      organization_id: box.id,
      user_id: user.id,
      opted_in_at: DateTime.utc_now(),
      division: division,
      birth_year: birth_year
    })
  end

  @uuid_columns ~w(id organization_id user_id class_type_id scheduled_class_id)a

  defp insert!(table, row) do
    row =
      row
      |> Map.put_new(:id, Ecto.UUID.generate())
      |> Map.new(fn
        {key, value} when key in @uuid_columns -> {key, Ecto.UUID.dump!(value)}
        {key, %DateTime{} = value} -> {key, DateTime.to_naive(value)}
        pair -> pair
      end)

    {1, _} = Repo.insert_all(table, [row])
  end

  defp audit_count(box, event_name) do
    Repo.aggregate(
      from(e in "analytics_events",
        where: e.organization_id == ^Ecto.UUID.dump!(box.id) and e.event_name == ^event_name
      ),
      :count
    )
  end

  defp execution!(ctx, member) do
    workout = workout_fixture(ctx.owner, %{tenant_context: ctx.context})
    at = DateTime.add(DateTime.utc_now(), -1, :day)

    %WorkoutExecution{organization_id: ctx.box.id}
    |> WorkoutExecution.start_changeset(%{
      user_id: member.id,
      master_workout_id: workout.id,
      source: :self_selected,
      status: :completed,
      started_at_utc: at,
      started_at_tz: "UTC"
    })
    |> Ecto.Changeset.put_change(:completed_at_utc, at)
    |> Ecto.Changeset.put_change(:completed_at_tz, "UTC")
    |> Ecto.Changeset.put_change(:total_elapsed_ms, 600_000)
    |> Repo.insert!()
  end
end

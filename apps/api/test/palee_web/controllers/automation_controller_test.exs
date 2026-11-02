defmodule PaleeWeb.AutomationControllerTest do
  @moduledoc """
  ADR-346/347 end to end: a box switches a ready recipe on, a domain event
  or the daily scan queues a message in the outbox, quiet hours hold it,
  the worker sends it through the first channel that reaches the person,
  and opting out stops it. «Σε κίνδυνο» scores members from their own
  attendance and its high level starts the win-back recipe.
  """
  use PaleeWeb.ConnCase, async: false

  alias Palee.Application.Automations.{DailyAutomations, DispatchAutomations}
  alias Palee.Application.Retention.MembersAtRisk
  alias Palee.{Automations, Notifications, Organizations, Repo}

  import Palee.TestFixtures

  setup do
    owner = admin_fixture(%{nickname: "auto_owner_#{System.unique_integer([:positive])}"})
    desk = user_fixture()

    {:ok, organization} =
      Organizations.create_organization(%{name: "Auto Box #{System.unique_integer([:positive])}"})

    add_member(organization, owner, :owner)
    add_member(organization, desk, :front_desk)
    activate_business!(organization.id)

    %{
      owner: owner,
      desk: desk,
      organization: organization,
      context: %{organization_id: organization.id},
      zone: Organizations.organization_timezone(organization.id)
    }
  end

  defp admin(ctx, path), do: "/api/org/#{ctx.organization.slug}/admin#{path}"

  defp switch_on(ctx, recipe, body \\ %{}) do
    build_conn()
    |> put_bearer_token(ctx.owner)
    |> put_req_header("content-type", "application/json")
    |> patch(admin(ctx, "/automations/#{recipe}"), Jason.encode!(Map.put(body, "enabled", true)))
    |> json_response(200)
  end

  defp deliveries(ctx), do: Automations.list_deliveries(ctx.context, %{})

  # Noon on the box's clock, a day after `date`... in UTC.
  defp local(date, hour, ctx), do: Automations.at_local_hour(date, hour, ctx.zone)

  describe "the recipes" do
    test "all off by default; only owners and admins change them", %{conn: conn} = ctx do
      body =
        conn
        |> put_bearer_token(ctx.owner)
        |> get(admin(ctx, "/automations"))
        |> json_response(200)

      assert Enum.map(body["recipes"], & &1["key"]) ==
               ~w(welcome trial_follow_up missed_classes renewal_reminder birthday win_back)

      assert Enum.all?(body["recipes"], &(&1["enabled"] == false))
      assert "in_app" in body["channels"] and "email" in body["channels"]

      welcome = Enum.find(body["recipes"], &(&1["key"] == "welcome"))
      assert welcome["default_subject"] =~ "Καλώς ήρθες"

      assert build_conn()
             |> put_bearer_token(ctx.desk)
             |> get(admin(ctx, "/automations"))
             |> json_response(403)

      assert %{"code" => "validation_failed", "errors" => %{"body" => _}} =
               build_conn()
               |> put_bearer_token(ctx.owner)
               |> put_req_header("content-type", "application/json")
               |> patch(
                 admin(ctx, "/automations/welcome"),
                 Jason.encode!(%{"body" => "Hi {name}"})
               )
               |> json_response(422)

      preview =
        build_conn()
        |> put_bearer_token(ctx.owner)
        |> put_req_header("content-type", "application/json")
        |> post(admin(ctx, "/automations/welcome/preview"), Jason.encode!(%{"locale" => "el"}))
        |> json_response(200)

      assert preview["body"] =~ "Μαρία"
      assert preview["body"] =~ ctx.organization.name
    end

    test "welcome: joining queues it, quiet hours hold it, the bell gets the box's words", ctx do
      %{"recipe" => recipe} =
        switch_on(ctx, "welcome", %{
          "channels" => ["in_app", "email"],
          "body" => "Γεια σου {first_name}! Το {box} σε περιμένει."
        })

      assert recipe["enabled"]
      member = user_fixture(%{nickname: "newbie_#{System.unique_integer([:positive])}"})
      add_member(ctx.organization, member, :member)

      assert [delivery] = deliveries(ctx)
      assert delivery.recipe == "welcome"
      assert delivery.user_id == member.id
      assert delivery.status == "pending"

      # Replaying the event queues nothing more.
      Palee.DomainEvents.publish(:membership_activated, %{
        organization_id: ctx.organization.id,
        user_id: member.id,
        at: DateTime.utc_now()
      })

      assert length(deliveries(ctx)) == 1

      # At 23:00 on the box's clock it waits for the morning.
      night = local(Date.utc_today() |> Date.add(1), 23, ctx)

      Repo.query!("UPDATE automation_deliveries SET due_at = $1 WHERE id = $2", [
        DateTime.add(night, -60, :second),
        Ecto.UUID.dump!(delivery.id)
      ])

      assert %{retried: 1} = DispatchAutomations.run(ctx.context, night)
      [waiting] = deliveries(ctx)
      assert waiting.status == "pending"

      assert DateTime.compare(waiting.due_at, local(Date.utc_today() |> Date.add(2), 9, ctx)) ==
               :eq

      assert %{sent: 1} = DispatchAutomations.run(ctx.context, waiting.due_at)
      [sent] = deliveries(ctx)
      assert sent.status == "sent"
      assert sent.channel == "in_app"

      [note] =
        member.id
        |> Notifications.list_for_user()
        |> Enum.filter(&(to_string(&1.type) == "box_automation"))

      assert note.payload["body"] =~ "Το #{ctx.organization.name} σε περιμένει"
      assert note.payload["body"] =~ "Γεια σου"

      # Sending again finds nothing due.
      assert %{sent: 0} = DispatchAutomations.run(ctx.context, DateTime.add(waiting.due_at, 600))
    end

    test "email when the box chose it; a former box member gets nothing", ctx do
      switch_on(ctx, "welcome", %{"channels" => ["email"], "delay_minutes" => 0})
      member = user_fixture()
      add_member(ctx.organization, member, :member)
      leaver = user_fixture()
      add_member(ctx.organization, leaver, :member)

      Repo.query!(
        "UPDATE organization_memberships SET status = 'revoked' WHERE user_id = $1 AND organization_id = $2",
        [Ecto.UUID.dump!(leaver.id), Ecto.UUID.dump!(ctx.organization.id)]
      )

      noon = local(Date.utc_today() |> Date.add(1), 12, ctx)
      assert %{sent: 1, skipped: 1} = DispatchAutomations.run(ctx.context, noon)

      by_user = Map.new(deliveries(ctx), &{&1.user_id, &1})
      assert by_user[member.id].channel == "email"
      assert by_user[leaver.id].skip_reason == "not_in_box"

      [email] = Palee.Email.list_by_idempotency_prefix("box_automation:" <> by_user[member.id].id)
      assert email.kind == "box_automation"
    end

    test "switching off or opting out cancels what was queued", ctx do
      switch_on(ctx, "welcome")
      one = user_fixture()
      two = user_fixture()
      add_member(ctx.organization, one, :member)
      add_member(ctx.organization, two, :member)

      prefs =
        build_conn()
        |> put_bearer_token(one)
        |> put_req_header("content-type", "application/json")
        |> put(
          "/api/org/#{ctx.organization.slug}/me/automatic-messages",
          Jason.encode!(%{"opted_out_recipes" => ["welcome"]})
        )
        |> json_response(200)

      assert prefs["opted_out_recipes"] == ["welcome"]
      statuses = Map.new(deliveries(ctx), &{&1.user_id, &1.status})
      assert statuses[one.id] == "cancelled"
      assert statuses[two.id] == "pending"

      build_conn()
      |> put_bearer_token(ctx.owner)
      |> put_req_header("content-type", "application/json")
      |> patch(admin(ctx, "/automations/welcome"), Jason.encode!(%{"enabled" => false}))
      |> json_response(200)

      assert Enum.all?(deliveries(ctx), &(&1.status == "cancelled"))

      history =
        build_conn()
        |> put_bearer_token(ctx.owner)
        |> get(admin(ctx, "/automations/messages"))
        |> json_response(200)

      assert length(history["deliveries"]) == 2
    end

    test "birthday: shared by the member, queued once a year after the send hour", ctx do
      switch_on(ctx, "birthday")
      member = user_fixture()
      add_member(ctx.organization, member, :member)
      today = Date.utc_today() |> Date.add(3)

      build_conn()
      |> put_bearer_token(member)
      |> put_req_header("content-type", "application/json")
      |> put(
        "/api/org/#{ctx.organization.slug}/me/automatic-messages",
        Jason.encode!(%{"birthday" => %{"month" => today.month, "day" => today.day}})
      )
      |> json_response(200)

      assert DailyAutomations.run(ctx.context, local(today, 8, ctx)) == 0
      assert DailyAutomations.run(ctx.context, local(today, 11, ctx)) == 1
      assert DailyAutomations.run(ctx.context, local(today, 15, ctx)) == 0

      assert [%{recipe: "birthday", trigger_ref: ref}] = deliveries(ctx)
      assert ref == "birthday:#{member.id}:#{today.year}"

      assert %{sent: 1} = DispatchAutomations.run(ctx.context, local(today, 11, ctx))
    end
  end

  describe "members at risk" do
    test "a member who stopped coming is high risk with reasons and starts the win-back", ctx do
      switch_on(ctx, "win_back")
      steady = user_fixture()
      gone = user_fixture()
      add_member(ctx.organization, steady, :member)
      add_member(ctx.organization, gone, :member)
      now = DateTime.utc_now()

      class_type = class_type_fixture(%{tenant_context: owner_context(ctx)})

      for days_ago <- [2, 5, 9, 12, 16, 19, 23, 26, 33, 40, 47, 54, 61, 68, 75, 82] do
        attend(ctx, class_type, steady, DateTime.add(now, -days_ago, :day))
      end

      for days_ago <- [30, 32, 35, 37, 40, 42, 45, 47, 50, 52, 55, 57, 60, 62, 65, 67] do
        attend(ctx, class_type, gone, DateTime.add(now, -days_ago, :day))
      end

      assert %{scored: 2, newly_high: 1} = MembersAtRisk.refresh(ctx.context, now)

      list =
        build_conn()
        |> put_bearer_token(ctx.desk)
        |> get(admin(ctx, "/members-at-risk"))
        |> json_response(200)

      assert [at_risk] = list["members"]
      assert at_risk["user_id"] == gone.id
      assert at_risk["level"] == "high"
      codes = Enum.map(at_risk["reasons"], & &1["code"])
      assert "absent" in codes and "attendance_drop" in codes
      assert at_risk["suggested_action"] == "personal_message"
      assert list["counts"]["high"] == 1

      # The win-back recipe queued once; a second run the same day adds nothing.
      assert [%{recipe: "win_back", user_id: user_id}] = deliveries(ctx)
      assert user_id == gone.id
      assert %{newly_high: 0} = MembersAtRisk.refresh(ctx.context, DateTime.add(now, 3600))
      assert length(deliveries(ctx)) == 1

      snoozed =
        build_conn()
        |> put_bearer_token(ctx.desk)
        |> put_req_header("content-type", "application/json")
        |> post(admin(ctx, "/members-at-risk/#{gone.id}/snooze"), Jason.encode!(%{"days" => 7}))
        |> json_response(200)

      assert snoozed["member"]["snoozed_until"]

      assert %{"members" => []} =
               build_conn()
               |> put_bearer_token(ctx.desk)
               |> get(admin(ctx, "/members-at-risk"))
               |> json_response(200)

      contacted =
        build_conn()
        |> put_bearer_token(ctx.desk)
        |> put_req_header("content-type", "application/json")
        |> post(
          admin(ctx, "/members-at-risk/#{gone.id}/contacted"),
          Jason.encode!(%{"channel" => "phone"})
        )
        |> json_response(200)

      assert contacted["member"]["contacted_by"]["user_id"] == ctx.desk.id

      # ADR-384: the member's detail keeps every action with who and when,
      # newest first; showing them again is logged too.
      build_conn()
      |> put_bearer_token(ctx.owner)
      |> put_req_header("content-type", "application/json")
      |> post(admin(ctx, "/members-at-risk/#{gone.id}/snooze"), Jason.encode!(%{"days" => 0}))
      |> json_response(200)

      detail =
        build_conn()
        |> put_bearer_token(ctx.desk)
        |> get(admin(ctx, "/members-at-risk/#{gone.id}"))
        |> json_response(200)

      assert detail["member"]["user_id"] == gone.id

      assert [
               %{
                 "kind" => "unsnoozed",
                 "actor" => %{"user_id" => owner_id},
                 "snoozed_until" => nil
               },
               %{"kind" => "contacted", "channel" => "phone", "actor" => %{"user_id" => desk_id}},
               %{
                 "kind" => "snoozed",
                 "snoozed_until" => until,
                 "actor" => %{"user_id" => desk_id}
               }
             ] = detail["actions"]

      assert owner_id == ctx.owner.id
      assert desk_id == ctx.desk.id
      assert until == snoozed["member"]["snoozed_until"]
      assert Enum.all?(detail["actions"], &is_binary(&1["at"]))

      # A former box member's log goes with their risk.
      Palee.Retention.delete_except(ctx.context, [])
      assert Palee.Retention.actions(ctx.context, gone.id, 50) == []
    end

    test "missed classes: an absence is greeted once", ctx do
      switch_on(ctx, "missed_classes", %{"settings" => %{"days_absent" => 10}})
      member = user_fixture()
      add_member(ctx.organization, member, :member)
      class_type = class_type_fixture(%{tenant_context: owner_context(ctx)})
      today = Date.utc_today()
      attend(ctx, class_type, member, local(Date.add(today, -12), 18, ctx))

      assert DailyAutomations.run(ctx.context, local(today, 12, ctx)) == 1
      assert DailyAutomations.run(ctx.context, local(Date.add(today, 1), 12, ctx)) == 0
      assert [%{recipe: "missed_classes", data: %{"days" => 12}}] = deliveries(ctx)
    end
  end

  defp owner_context(ctx) do
    {:ok, context} = Organizations.resolve_tenant_context(ctx.owner, ctx.organization.slug)
    context
  end

  defp attend(ctx, class_type, user, at) do
    class_id = Ecto.UUID.generate()
    at = at |> DateTime.truncate(:second) |> DateTime.to_naive()

    Repo.query!(
      """
      INSERT INTO scheduled_classes (id, organization_id, class_type_id, scheduled_at, capacity, inserted_at, updated_at)
      VALUES ($1, $2, $3, $4, 10, now(), now())
      """,
      [
        Ecto.UUID.dump!(class_id),
        Ecto.UUID.dump!(ctx.organization.id),
        Ecto.UUID.dump!(class_type.id),
        at
      ]
    )

    Repo.query!(
      """
      INSERT INTO class_attendance_records (id, organization_id, scheduled_class_id, user_id, status, marked_at, inserted_at, updated_at)
      VALUES ($1, $2, $3, $4, 'attended', $5, now(), now())
      """,
      [
        Ecto.UUID.dump!(Ecto.UUID.generate()),
        Ecto.UUID.dump!(ctx.organization.id),
        Ecto.UUID.dump!(class_id),
        Ecto.UUID.dump!(user.id),
        at
      ]
    )
  end

  defp add_member(organization, user, role) do
    {:ok, membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: user.id,
        role: role,
        status: :active,
        joined_at: DateTime.add(DateTime.utc_now(), -200, :day)
      })

    membership
  end
end

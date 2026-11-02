defmodule PaleeWeb.AdminChannelClassNoticesControllerTest do
  @moduledoc """
  ADR-385 over HTTP: «Ενημέρωση συμμετεχόντων» of a class goes in the app to
  participants with a push device and by SMS to the rest who agreed; the
  preview counts and prices it first, a repeated press sends nothing twice,
  and the month's usage says staff spent it.
  """

  use PaleeWeb.ConnCase, async: false

  import Palee.TestFixtures

  alias Palee.{Notifications, Organizations, Repo}
  alias Palee.Scheduling.{Booking, ClassType, ScheduledClass}

  setup %{conn: conn} do
    owner = admin_fixture(%{nickname: "cn_owner"})
    coach = user_fixture(%{nickname: "cn_coach"})

    {:ok, organization} =
      Organizations.create_organization(%{name: "Notices #{System.unique_integer([:positive])}"})

    members =
      for name <- ~w(cn_app cn_sms cn_none) do
        user_fixture(%{nickname: name})
      end

    for {user, role} <- [{owner, :owner}, {coach, :coach}] ++ Enum.map(members, &{&1, :member}) do
      {:ok, _} =
        Organizations.add_membership(%{
          organization_id: organization.id,
          user_id: user.id,
          role: role,
          status: :active,
          joined_at: DateTime.utc_now()
        })
    end

    class_type =
      Repo.insert!(%ClassType{
        organization_id: organization.id,
        name: "CrossFit",
        slug: "crossfit-#{System.unique_integer([:positive])}"
      })

    slot =
      Repo.insert!(%ScheduledClass{
        organization_id: organization.id,
        class_type_id: class_type.id,
        name: "WOD",
        scheduled_at: DateTime.add(DateTime.utc_now(), 1, :day) |> DateTime.truncate(:second),
        capacity: 10
      })

    for member <- members do
      Repo.insert!(%Booking{
        organization_id: organization.id,
        scheduled_class_id: slot.id,
        user_id: member.id,
        status: :approved
      })
    end

    [app, sms, none] = members

    {:ok, _subscription, _} =
      Notifications.save_push_subscription(app.id, %{
        endpoint: "https://push.example.test/cn",
        expiration_time: nil,
        keys: %{"p256dh" => "k", "auth" => "k"}
      })

    %{
      owner: put_bearer_token(conn, owner),
      coach: put_bearer_token(conn, coach),
      sms: sms,
      none: none,
      slot: slot,
      base: "/api/org/#{organization.slug}/admin/channels"
    }
  end

  defp send_json(conn, method, path, body) do
    conn
    |> recycle()
    |> put_req_header("content-type", "application/json")
    |> dispatch(@endpoint, method, path, Jason.encode!(body))
  end

  test "staff without message_from_box are refused", ctx do
    assert ctx.coach
           |> send_json(:post, "#{ctx.base}/class-notices/preview", %{
             slot_id: ctx.slot.id,
             kind: "cancelled"
           })
           |> json_response(403)
  end

  test "without a connection every SMS is blocked, said once", ctx do
    assert %{"in_app" => 1, "sms" => 0, "unreachable" => 2, "sms_blocked" => blocked} =
             ctx.owner
             |> send_json(:post, "#{ctx.base}/class-notices/preview", %{
               slot_id: ctx.slot.id,
               kind: "cancelled"
             })
             |> json_response(200)

    assert blocked == "channels_not_connected"
  end

  test "the app first, SMS for the rest who agreed; sent once", ctx do
    ctx.owner
    |> send_json(:put, "#{ctx.base}/settings", %{
      provider: "sandbox",
      channels: ["sms"],
      quiet_start: nil,
      quiet_end: nil
    })
    |> json_response(200)

    %{"contact" => %{"id" => contact_id}} =
      ctx.owner
      |> send_json(:put, "#{ctx.base}/contacts", %{user_id: ctx.sms.id, phone: "6912345678"})
      |> json_response(200)

    ctx.owner
    |> send_json(:put, "#{ctx.base}/contacts/#{contact_id}/consents", %{
      channel: "sms",
      purpose: "service",
      granted: true
    })
    |> json_response(200)

    body = %{slot_id: ctx.slot.id, kind: "cancelled", locale: "el"}

    assert %{
             "participants" => 3,
             "in_app" => 1,
             "sms" => 1,
             "unreachable" => 1,
             "unreachable_reasons" => %{"channel_contact_missing" => 1},
             "estimated_cost_cents" => cost,
             "urgent" => true,
             "sample" => %{"body" => text, "held_for_quiet_hours" => false},
             "sms_blocked" => nil
           } =
             ctx.owner
             |> send_json(:post, "#{ctx.base}/class-notices/preview", body)
             |> json_response(200)

    assert cost > 0
    assert text =~ "WOD"

    assert %{"code" => "validation_failed", "errors" => %{"idempotency_key" => _}} =
             ctx.owner
             |> send_json(:post, "#{ctx.base}/class-notices", body)
             |> json_response(422)

    sent = Map.put(body, :idempotency_key, "press-1")

    for _press <- 1..2 do
      assert %{"in_app" => 1, "sms" => 1} =
               ctx.owner
               |> send_json(:post, "#{ctx.base}/class-notices", sent)
               |> json_response(200)
    end

    assert %{"total" => 1, "messages" => [%{"template_key" => "class_cancelled"}]} =
             ctx.owner
             |> recycle()
             |> get("#{ctx.base}/messages?source_ref=class:#{ctx.slot.id}")
             |> json_response(200)

    assert %{
             "by_source" => %{"staff" => %{"count" => 1}},
             "by_status" => by_status,
             "segments" => segments
           } =
             ctx.owner |> recycle() |> get("#{ctx.base}/usage") |> json_response(200)

    assert segments >= 1
    assert Enum.sum(Map.values(by_status)) == 1
  end

  test "a free notice needs its text", ctx do
    assert %{"errors" => %{"text" => ["required"]}} =
             ctx.owner
             |> send_json(:post, "#{ctx.base}/class-notices/preview", %{
               slot_id: ctx.slot.id,
               kind: "free"
             })
             |> json_response(422)
  end
end

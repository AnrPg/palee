defmodule PaleeWeb.OpenPlatformTest do
  @moduledoc """
  ADR-378..381 end to end over HTTP: API keys and the public API v1
  (scopes, the maker's rights, idempotency, preview, problem details, the
  OpenAPI document), signed webhooks with their log and replay, the email
  list with members' own consent, and doors.
  """

  use PaleeWeb.ConnCase, async: false

  import Palee.TestFixtures

  alias Palee.Application.Integrations.WebhookEvents
  alias Palee.Integrations.Domain.{AudienceSyncPlan, WebhookSignature}
  alias Palee.{Facility, Integrations, Organizations, Repo, Scheduling}

  setup do
    {:ok, organization} =
      Organizations.create_organization(%{name: "Open Box #{System.unique_integer([:positive])}"})

    Repo.query!("SELECT set_config($1, $2, false)", ["app.organization_id", organization.id])

    owner = user_fixture()
    add_member(organization, owner, :owner)
    {:ok, context} = Organizations.resolve_tenant_context(owner, organization.slug)

    {:ok, location} =
      Facility.create_location(context, %{name: "Κεντρικό", address: "Οδός 1", city: "Αθήνα"})

    class_type = class_type_fixture(%{tenant_context: context})
    workout = workout_fixture(owner, %{tenant_context: context, title: "Open WOD"})

    %{
      organization: organization,
      owner: owner,
      context: context,
      location: location,
      class_type: class_type,
      workout: workout,
      admin: "/api/org/#{organization.slug}/admin"
    }
  end

  # ------------------------------------------------------------------ helpers

  defp add_member(organization, user, role \\ :member) do
    {:ok, _membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: user.id,
        role: role,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    user
  end

  defp as(user), do: build_conn() |> put_bearer_token(user)

  defp make_key(ctx, scopes, user \\ nil) do
    as(user || ctx.owner)
    |> post("#{ctx.admin}/integrations/api-keys", %{name: "Zapier", scopes: scopes})
    |> json_response(201)
  end

  defp api(token), do: build_conn() |> put_req_header("authorization", "Bearer " <> token)

  defp problem(conn, status) do
    assert conn.status == status
    assert ["application/problem+json" <> _] = get_resp_header(conn, "content-type")
    body = Jason.decode!(conn.resp_body)
    assert body["type"] == "urn:palee:problem:" <> body["code"]
    assert body["status"] == status
    assert is_binary(body["title"])
    body
  end

  defp slot(ctx, minutes_from_now) do
    slot_fixture(ctx.workout, %{
      tenant_context: ctx.context,
      auto_approve: true,
      location_id: ctx.location.id,
      scheduled_at:
        DateTime.utc_now() |> DateTime.add(minutes_from_now * 60) |> DateTime.truncate(:second)
    })
  end

  defp book(ctx, user, slot) do
    {:ok, context} = Organizations.resolve_tenant_context(user, ctx.organization.slug)
    {:ok, booking} = Scheduling.submit_auto_approved_booking(context, user.id, slot.id)
    booking
  end

  # Records what the webhook receiver got, answering `status`.
  defp receiver(status) do
    test = self()

    Req.Test.stub(Palee.WebhookHttp, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test, {:webhook, conn.request_path, Plug.Conn.get_req_header(conn, "palee-signature"), body})
      Plug.Conn.send_resp(conn, status, "ok")
    end)
  end

  # ------------------------------------------------------------------ keys

  describe "API keys and the public API" do
    test "a key is shown once, listed masked, and reads within its scopes", ctx do
      %{"key" => key, "token" => token} = make_key(ctx, ["members:read"])

      assert token =~ ~r/\Apalee_test_[a-z2-7]{12}_[a-z2-7]{40}\z/
      assert key["scopes"] == ["members:read"]
      assert key["status"] == "active"

      %{"keys" => [listed]} = as(ctx.owner) |> get("#{ctx.admin}/integrations/api-keys") |> json_response(200)
      assert listed["masked"] == "palee_test_#{key["prefix"]}_…"
      refute Map.has_key?(listed, "token")
      refute inspect(listed) =~ token

      me = api(token) |> get("/api/public/v1/me") |> json_response(200)
      assert me["box"]["id"] == ctx.organization.id
      assert me["key"]["scopes"] == ["members:read"]

      %{"data" => people, "next_cursor" => nil} =
        api(token) |> get("/api/public/v1/members?limit=10") |> json_response(200)

      assert ctx.owner.id in Enum.map(people, & &1["id"])

      assert %{"code" => "insufficient_scope"} =
               api(token) |> get("/api/public/v1/payments") |> problem(403)

      assert %{"code" => "validation_failed", "errors" => %{"limit" => _}} =
               api(token) |> get("/api/public/v1/members?limit=500") |> problem(422)

      # The last use is remembered.
      assert %{last_used_at: %DateTime{}} =
               ctx.context |> Integrations.list_api_keys() |> hd()
    end

    test "no key, a wrong key or a made-up key answer 401 with a challenge", ctx do
      %{"token" => token} = make_key(ctx, ["members:read"])

      for conn <- [
            build_conn(),
            api("palee_test_aaaaaaaaaaaa_" <> String.duplicate("a", 40)),
            api(String.replace(token, ~r/.$/, "x")),
            api("nonsense")
          ] do
        conn = get(conn, "/api/public/v1/me")
        assert %{"code" => "invalid_api_key"} = problem(conn, 401)
        assert [challenge] = get_resp_header(conn, "www-authenticate")
        assert challenge =~ "Bearer"
      end
    end

    test "rotation keeps the old secret for 24 hours; revoking stops the key at once", ctx do
      %{"key" => %{"id" => id}, "token" => old} = make_key(ctx, ["members:read"])

      %{"token" => new, "key" => rotated} =
        as(ctx.owner) |> post("#{ctx.admin}/integrations/api-keys/#{id}/rotate") |> json_response(200)

      refute new == old
      assert rotated["previous_secret_expires_at"]
      assert api(new) |> get("/api/public/v1/me") |> json_response(200)
      assert api(old) |> get("/api/public/v1/me") |> json_response(200)

      assert %{"key" => %{"status" => "revoked"}} =
               as(ctx.owner) |> delete("#{ctx.admin}/integrations/api-keys/#{id}") |> json_response(200)

      assert %{"code" => "invalid_api_key"} = api(new) |> get("/api/public/v1/me") |> problem(401)
      assert %{"code" => "invalid_api_key"} = api(old) |> get("/api/public/v1/me") |> problem(401)
    end

    test "a key never does more than its maker can now", ctx do
      admin = add_member(ctx.organization, user_fixture(), :admin)
      %{"token" => token} = make_key(ctx, ["members:read"], admin)

      assert api(token) |> get("/api/public/v1/members") |> json_response(200)

      {:ok, _membership} =
        Palee.Application.ChangeMembershipRoles.set_role(ctx.context, admin.id, "member")

      assert %{"code" => "forbidden"} = api(token) |> get("/api/public/v1/members") |> problem(403)
    end

    test "members cannot make keys; scopes must be known", ctx do
      member = add_member(ctx.organization, user_fixture())

      as(member)
      |> post("#{ctx.admin}/integrations/api-keys", %{name: "x", scopes: ["members:read"]})
      |> json_response(403)

      assert %{"code" => "invalid_scopes"} =
               as(ctx.owner)
               |> post("#{ctx.admin}/integrations/api-keys", %{name: "x", scopes: ["payments:write"]})
               |> json_response(422)
    end

    test "commands: preview writes nothing, Idempotency-Key runs once, another body is refused", ctx do
      %{"token" => token} = make_key(ctx, ["classes:read", "classes:write"])
      starts_at = DateTime.utc_now() |> DateTime.add(2, :day) |> DateTime.truncate(:second)

      body = %{
        class_type_id: ctx.class_type.id,
        starts_at: DateTime.to_iso8601(starts_at),
        duration_minutes: 60,
        capacity: 12,
        location_id: ctx.location.id
      }

      preview =
        api(token)
        |> put_req_header("palee-preview", "true")
        |> post("/api/public/v1/classes", body)
        |> json_response(200)

      assert preview["preview"]
      assert count_classes(ctx, starts_at) == 0

      first =
        api(token)
        |> put_req_header("idempotency-key", "class-1")
        |> post("/api/public/v1/classes", body)

      created = json_response(first, 201)
      assert get_resp_header(first, "idempotent-replayed") == []

      again =
        api(token)
        |> put_req_header("idempotency-key", "class-1")
        |> post("/api/public/v1/classes", Map.put(body, :duration_minutes, 60))

      assert json_response(again, 201)["id"] == created["id"]
      assert get_resp_header(again, "idempotent-replayed") == ["true"]
      assert count_classes(ctx, starts_at) == 1

      assert %{"code" => "idempotency_key_reused"} =
               api(token)
               |> put_req_header("idempotency-key", "class-1")
               |> post("/api/public/v1/classes", Map.put(body, :capacity, 13))
               |> problem(409)

      assert %{"code" => "invalid_idempotency_key"} =
               api(token)
               |> put_req_header("idempotency-key", "with space")
               |> post("/api/public/v1/classes", body)
               |> problem(422)

      assert %{"id" => id} = api(token) |> get("/api/public/v1/classes/#{created["id"]}") |> json_response(200)
      assert id == created["id"]
    end

    test "the OpenAPI document is generated from the registry and needs no key" do
      doc = build_conn() |> get("/api/public/v1/openapi.json") |> json_response(200)

      assert doc["openapi"] == "3.1.0"
      assert String.ends_with?(hd(doc["servers"])["url"], "/api/public/v1")
      assert doc["paths"]["/members/{id}"]["get"]["operationId"] == "members.get"
      assert doc["paths"]["/bookings"]["post"]["x-palee-scope"] == "bookings:write"
      assert doc["paths"]["/payments"]["get"]["x-palee-risk"] == "read"
      refute Map.has_key?(doc["paths"]["/payments"], "post")
      assert Map.has_key?(doc["webhooks"], "booking.created")

      for {_path, operations} <- doc["paths"], {_method, operation} <- operations do
        assert Map.has_key?(operation["responses"], "default")

        if schema = get_in(operation, ["requestBody", "content", "application/json", "schema"]) do
          assert schema["required"] == Enum.sort(schema["required"])
        end
      end
    end
  end

  defp count_classes(ctx, starts_at) do
    ctx.context
    |> Scheduling.get_calendar_week(%{
      start_at: DateTime.add(starts_at, -60),
      end_at: DateTime.add(starts_at, 60),
      class_type_ids: [],
      include_drafts: true
    })
    |> length()
  end

  # ------------------------------------------------------------------ webhooks

  describe "webhooks" do
    test "deliveries are signed, logged, retried, replayed and a 410 turns the endpoint off", ctx do
      %{"endpoint" => endpoint, "secret" => secret} =
        as(ctx.owner)
        |> post("#{ctx.admin}/integrations/webhooks", %{
          url: "https://hooks.example.com/palee",
          events: ["booking.created", "payment.recorded"]
        })
        |> json_response(201)

      assert secret =~ ~r/\Awhsec_/
      refute inspect(as(ctx.owner) |> get("#{ctx.admin}/integrations/webhooks") |> json_response(200)) =~ secret

      # «Δοκιμή»: a signed ping.
      receiver(200)

      %{"delivery" => ping} =
        as(ctx.owner) |> post("#{ctx.admin}/integrations/webhooks/#{endpoint["id"]}/test") |> json_response(200)

      assert ping["status"] == "succeeded"
      assert_received {:webhook, "/palee", [signature], body}
      assert :ok = WebhookSignature.verify(secret, signature, body, System.system_time(:second))
      assert %{"type" => "ping", "api_version" => _} = Jason.decode!(body)

      # A domain event becomes one thin delivery; the receiver fails, it is retried later.
      receiver(500)
      member_id = Ecto.UUID.generate()

      :ok =
        WebhookEvents.handle(
          :booking_made,
          %{booking_id: Ecto.UUID.generate(), scheduled_class_id: Ecto.UUID.generate(), user_id: member_id},
          ctx.organization.id,
          DateTime.utc_now()
        )

      assert_received {:webhook, "/palee", [_signature], event_body}
      event = Jason.decode!(event_body)
      assert event["type"] == "booking.created"
      assert event["data"]["member_id"] == member_id
      assert Map.keys(event["data"]) |> Enum.sort() == ~w(booking_id class_id member_id)

      %{"deliveries" => [failed | _], "total" => 2} =
        as(ctx.owner)
        |> get("#{ctx.admin}/integrations/webhooks/#{endpoint["id"]}/deliveries")
        |> json_response(200)

      assert failed["event_type"] == "booking.created"
      assert failed["status"] == "pending"
      assert failed["attempts"] == 1
      assert failed["last_status_code"] == 500
      assert failed["next_attempt_at"]

      %{"delivery" => detail} =
        as(ctx.owner) |> get("#{ctx.admin}/integrations/deliveries/#{failed["id"]}") |> json_response(200)

      assert [%{"outcome" => "failed", "status_code" => 500}] = detail["attempts_log"]

      # «Ξανά» after the receiver is fixed: the same event id, a new delivery.
      receiver(200)

      %{"delivery" => replayed} =
        as(ctx.owner) |> post("#{ctx.admin}/integrations/deliveries/#{ping["id"]}/replay") |> json_response(200)

      assert replayed["status"] == "succeeded"
      assert replayed["event_id"] == ping["event_id"]
      assert replayed["replay_of_id"] == ping["id"]

      # 410 Gone: failed at once and the endpoint is switched off.
      receiver(410)
      as(ctx.owner) |> post("#{ctx.admin}/integrations/webhooks/#{endpoint["id"]}/test") |> json_response(200)

      %{"webhooks" => [off]} = as(ctx.owner) |> get("#{ctx.admin}/integrations/webhooks") |> json_response(200)
      assert off["status"] == "disabled"
      assert off["disabled_reason"] == "gone"
    end

    test "private and plain-http addresses are refused", ctx do
      for url <- ["http://hooks.example.com/x", "https://127.0.0.1/x", "https://169.254.169.254/x"] do
        assert %{"code" => "invalid_webhook_url"} =
                 as(ctx.owner)
                 |> post("#{ctx.admin}/integrations/webhooks", %{url: url, events: ["booking.created"]})
                 |> json_response(422)
      end
    end

    test "Zapier and Make subscribe with REST hooks within the key's scopes", ctx do
      %{"token" => token} = make_key(ctx, ["bookings:read", "webhooks:write"])

      subscription =
        api(token)
        |> post("/api/public/v1/webhook-subscriptions", %{
          url: "https://hooks.zapier.com/hooks/standard/1/abc",
          events: ["booking.created"]
        })
        |> json_response(201)

      assert subscription["secret"] =~ ~r/\Awhsec_/

      assert %{"code" => "insufficient_scope"} =
               api(token)
               |> post("/api/public/v1/webhook-subscriptions", %{
                 url: "https://hooks.zapier.com/hooks/standard/1/def",
                 events: ["payment.recorded"]
               })
               |> problem(403)

      %{"webhooks" => [listed]} = as(ctx.owner) |> get("#{ctx.admin}/integrations/webhooks") |> json_response(200)
      assert listed["source"] == "api"

      assert api(token)
             |> delete("/api/public/v1/webhook-subscriptions/#{subscription["id"]}")
             |> response(200)

      assert %{"webhooks" => []} = as(ctx.owner) |> get("#{ctx.admin}/integrations/webhooks") |> json_response(200)
    end
  end

  # ------------------------------------------------------------------ email list

  describe "email list and marketing consent" do
    test "only members who said yes are sent, email and first name only; no takes them off", ctx do
      member = add_member(ctx.organization, user_fixture(%{display_name: "Μαρία Παπαδοπούλου"}))
      _silent = add_member(ctx.organization, user_fixture())
      test = self()

      Req.Test.stub(Palee.AudienceHttp, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test, {:mailchimp, conn.method, conn.request_path, body})
        Req.Test.json(conn, %{"id" => "x"})
      end)

      %{"connection" => connection} =
        as(ctx.owner)
        |> put("#{ctx.admin}/integrations/email-list", %{
          provider: "mailchimp",
          list_id: "abc123",
          api_key: "0123456789abcdef0123456789abcdef-us21"
        })
        |> json_response(200)

      assert connection["key_saved"]
      refute inspect(connection) =~ "us21"
      assert_received {:mailchimp, "GET", "/3.0/lists/abc123", _body}
      # Nobody has said yes yet: nothing is sent.
      refute_received {:mailchimp, "PUT", _path, _body}

      path = "/api/org/#{ctx.organization.slug}/me/marketing-consent"
      assert %{"granted" => false, "list_connected" => true} = as(member) |> get(path) |> json_response(200)

      assert %{"granted" => true, "granted_at" => granted_at} =
               as(member) |> put(path, %{granted: true}) |> json_response(200)

      hash = AudienceSyncPlan.mailchimp_subscriber_hash(member.email)
      member_path = "/3.0/lists/abc123/members/#{hash}"
      assert_received {:mailchimp, "PUT", ^member_path, body}

      assert %{"email_address" => _, "status" => "subscribed", "merge_fields" => %{"FNAME" => _}} =
               sent = Jason.decode!(body)

      assert Map.keys(sent["merge_fields"]) == ["FNAME"]
      refute_received {:mailchimp, "PUT", _other, _body}

      assert %{"granted" => false, "granted_at" => ^granted_at, "withdrawn_at" => withdrawn} =
               as(member) |> put(path, %{granted: false}) |> json_response(200)

      assert withdrawn
      assert_received {:mailchimp, "PATCH", ^member_path, unsubscribe}
      assert %{"status" => "unsubscribed"} = Jason.decode!(unsubscribe)
    end

    test "a refused key is not saved", ctx do
      Req.Test.stub(Palee.AudienceHttp, &Plug.Conn.send_resp(&1, 401, ~s({"title":"API Key Invalid"})))

      assert %{"code" => "audience_unauthorized"} =
               as(ctx.owner)
               |> put("#{ctx.admin}/integrations/email-list", %{
                 provider: "brevo",
                 list_id: "7",
                 api_key: "xkeysib-0123456789abcdef"
               })
               |> json_response(422)

      assert %{"connection" => nil} =
               as(ctx.owner) |> get("#{ctx.admin}/integrations/email-list") |> json_response(200)

    end
  end

  # ------------------------------------------------------------------ doors

  describe "doors" do
    defp door_code(ctx) do
      as(ctx.owner)
      |> get("#{ctx.admin}/check-in/door/#{ctx.location.id}")
      |> json_response(200)
      |> Map.fetch!("code")
    end

    defp open(ctx, user, extra \\ %{}) do
      as(user)
      |> post("/api/access/open", Map.merge(%{location_id: ctx.location.id, code: door_code(ctx)}, extra))
    end

    defp make_door(ctx, attrs) do
      as(ctx.owner)
      |> post(
        "#{ctx.admin}/doors",
        Map.merge(%{name: "Κεντρική είσοδος", location_id: ctx.location.id, provider: "sandbox"}, attrs)
      )
      |> json_response(201)
    end

    test "a member with a booking in the window opens it; others are refused; all is logged", ctx do
      %{"door" => door, "event_url" => event_url} = make_door(ctx, %{})
      assert door["rules"]["who"] == "booked_or_covered"
      refute door["credentials_saved"]
      assert event_url =~ "/api/access/doors/#{door["id"]}/events?token="

      booked = add_member(ctx.organization, user_fixture())
      book(ctx, booked, slot(ctx, 10))
      walk_in = add_member(ctx.organization, user_fixture())
      stranger = user_fixture()

      assert %{"opened" => true, "reason" => "booked_class", "seconds" => 5} =
               open(ctx, booked) |> json_response(200)

      assert %{"code" => "entry_denied", "params" => %{"reason" => "no_booking_in_window"}} =
               open(ctx, walk_in) |> json_response(403)

      assert %{"opened" => true, "reason" => "staff"} = open(ctx, ctx.owner) |> json_response(200)
      refute open(ctx, stranger).status == 200

      %{"events" => events} = as(ctx.owner) |> get("#{ctx.admin}/access-events") |> json_response(200)
      kinds = Enum.map(events, &{&1["kind"], &1["reason"], &1["user_id"]})
      assert {"granted", "booked_class", booked.id} in kinds
      assert {"denied", "no_booking_in_window", walk_in.id} in kinds
      assert {"granted", "staff", ctx.owner.id} in kinds
    end

    test "an offline controller keeps the door locked and sends the member to the desk", ctx do
      %{"door" => door} = make_door(ctx, %{settings: %{simulate: "offline"}, rules: %{who: "members"}})
      member = add_member(ctx.organization, user_fixture())

      assert %{"code" => "door_offline"} = open(ctx, member) |> json_response(503)

      assert %{"code" => "door_offline"} =
               as(ctx.owner) |> post("#{ctx.admin}/doors/#{door["id"]}/unlock") |> json_response(503)

      %{"events" => events} =
        as(ctx.owner) |> get("#{ctx.admin}/access-events?kind=unlock_failed") |> json_response(200)

      assert length(events) == 2
      assert %{"doors" => [%{"last_error" => "offline" <> _}]} =
               as(ctx.owner) |> get("#{ctx.admin}/doors") |> json_response(200)
    end

    test "two doors at a branch: the member chooses", ctx do
      %{"door" => first} = make_door(ctx, %{rules: %{who: "members"}})
      _second = make_door(ctx, %{name: "Πίσω πόρτα", rules: %{who: "members"}})
      member = add_member(ctx.organization, user_fixture())

      assert %{"code" => "choose_door", "params" => %{"doors" => doors}} =
               open(ctx, member) |> json_response(409)

      assert length(doors) == 2

      assert %{"opened" => true, "door" => %{"id" => id}} =
               open(ctx, member, %{door_id: first["id"]}) |> json_response(200)

      assert id == first["id"]
    end

    test "a Shelly relay is checked when saved, pulsed with toggle_after, and posts its events", ctx do
      test = self()

      Req.Test.stub(Palee.DoorHttp, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test, {:shelly, conn.host, conn.request_path, conn.query_params, Jason.decode!(body)})

        case conn.request_path do
          "/v2/devices/api/get" -> Req.Test.json(conn, [%{"id" => "a8032ab12345", "online" => true}])
          _set -> Req.Test.json(conn, %{})
        end
      end)

      %{"door" => door, "event_url" => event_url} =
        make_door(ctx, %{
          provider: "shelly",
          settings: %{server: "shelly-77-eu.shelly.cloud", device_id: "a8032ab12345", channel: 0},
          credentials: %{auth_key: String.duplicate("k", 40)},
          rules: %{who: "members", unlock_seconds: 3}
        })

      assert door["credentials_saved"]
      refute inspect(door) =~ String.duplicate("k", 40)
      assert_received {:shelly, "shelly-77-eu.shelly.cloud", "/v2/devices/api/get", %{"auth_key" => _}, _body}

      member = add_member(ctx.organization, user_fixture())
      assert %{"opened" => true, "seconds" => 3} = open(ctx, member) |> json_response(200)

      assert_received {:shelly, _host, "/v2/devices/api/set/switch", _query,
                       %{"id" => "a8032ab12345", "channel" => 0, "on" => true, "toggle_after" => 3}}

      # The relay's own action (GET with the door's token).
      %URI{path: path, query: query} = URI.parse(event_url)

      assert %{"recorded" => 1} =
               build_conn() |> get("#{path}?#{query}&event=door_opened") |> json_response(200)

      assert %{"code" => "not_found"} =
               build_conn() |> get("#{path}?token=wrong&event=door_opened") |> json_response(404)

      %{"events" => events} =
        as(ctx.owner) |> get("#{ctx.admin}/access-events?kind=door_event") |> json_response(200)

      assert [%{"provider_event" => "door_opened", "method" => "provider"}] = events
    end

    test "a front desk opens doors but cannot set them up", ctx do
      %{"door" => door} = make_door(ctx, %{})
      desk = add_member(ctx.organization, user_fixture(), :front_desk)

      assert %{"opened" => true} =
               as(desk) |> post("#{ctx.admin}/doors/#{door["id"]}/unlock") |> json_response(200)

      as(desk)
      |> post("#{ctx.admin}/doors", %{name: "x", location_id: ctx.location.id, provider: "sandbox"})
      |> json_response(403)

      %{"events" => [event]} =
        as(ctx.owner) |> get("#{ctx.admin}/access-events?kind=staff_unlock") |> json_response(200)

      assert event["actor_id"] == desk.id
    end
  end
end

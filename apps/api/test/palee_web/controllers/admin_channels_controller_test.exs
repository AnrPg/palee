defmodule PaleeWeb.AdminChannelsControllerTest do
  @moduledoc """
  ADR-348..351 over HTTP: the owner connects the sandbox provider, records
  a member's number and consent, previews and sends an SMS; the member
  manages their own number and consents; the provider's webhook reports
  delivery. Coaches without the capabilities are refused; the secret is
  never returned.
  """

  use PaleeWeb.ConnCase, async: false

  import Palee.TestFixtures

  alias Palee.Infrastructure.Channels.SandboxChannel
  alias Palee.Organizations

  setup %{conn: conn} do
    owner = admin_fixture(%{nickname: "ch_owner"})
    coach = user_fixture(%{nickname: "ch_coach"})
    member = user_fixture(%{nickname: "ch_member"})

    {:ok, organization} =
      Organizations.create_organization(%{name: "Channels #{System.unique_integer([:positive])}"})

    for {user, role} <- [{owner, :owner}, {coach, :coach}, {member, :member}] do
      {:ok, _} =
        Organizations.add_membership(%{
          organization_id: organization.id,
          user_id: user.id,
          role: role,
          status: :active,
          joined_at: DateTime.utc_now()
        })
    end

    %{
      owner: put_bearer_token(conn, owner),
      coach: put_bearer_token(conn, coach),
      member_conn: put_bearer_token(conn, member),
      member: member,
      organization: organization,
      base: "/api/org/#{organization.slug}/admin/channels",
      me: "/api/org/#{organization.slug}/me/channels"
    }
  end

  defp send_json(conn, method, path, body) do
    conn
    |> recycle()
    |> put_req_header("content-type", "application/json")
    |> dispatch(@endpoint, method, path, Jason.encode!(body))
  end

  defp get_json(conn, path), do: conn |> recycle() |> get(path)

  test "staff without the capabilities are refused", ctx do
    assert ctx.coach |> get_json("#{ctx.base}/settings") |> json_response(403)
    assert ctx.coach |> get_json("#{ctx.base}/messages") |> json_response(403)
  end

  test "settings: connect, check, usage; the secret never comes back", ctx do
    assert %{"connection" => nil, "providers" => providers, "usage" => %{"spent_cents" => 0}} =
             ctx.owner |> get_json("#{ctx.base}/settings") |> json_response(200)

    assert Enum.any?(providers, &(&1["provider"] == "brevo"))

    assert %{"connection" => connection, "check" => %{"ok" => true}} =
             ctx.owner
             |> send_json(:put, "#{ctx.base}/settings", %{
               provider: "sandbox",
               account_mode: "own",
               secret: "sandbox-secret",
               channels: ["sms"],
               monthly_budget_cents: 500,
               quiet_start: "22:00",
               quiet_end: "08:00"
             })
             |> json_response(200)

    assert connection["has_secret"]
    refute Map.has_key?(connection, "secret")
    assert connection["quiet_start"] == "22:00"
    assert connection["webhook_url"] =~ "/api/webhooks/channels/#{ctx.organization.id}/"

    assert %{"code" => "validation_failed", "errors" => %{"quiet_hours" => ["invalid"]}} =
             ctx.owner
             |> send_json(:put, "#{ctx.base}/settings", %{
               provider: "sandbox",
               quiet_start: "22:00",
               quiet_end: nil
             })
             |> json_response(422)

    assert %{"cap_cents" => 500} =
             ctx.owner |> get_json("#{ctx.base}/usage?month=2026-10") |> json_response(200)

    assert %{"templates" => templates} =
             ctx.owner |> get_json("#{ctx.base}/templates") |> json_response(200)

    assert Enum.any?(templates, &(&1["key"] == "class_cancelled"))

    assert %{"locale" => "el", "body" => "{{box}}: Ακύρωση {{class}}"} =
             ctx.owner
             |> send_json(:put, "#{ctx.base}/templates/class_cancelled", %{
               locale: "el",
               body: "{{box}}: Ακύρωση {{class}}"
             })
             |> json_response(200)

    assert ctx.owner
           |> recycle()
           |> delete("#{ctx.base}/templates/class_cancelled?locale=el")
           |> response(204)
  end

  test "a staff SMS: number, consent, preview, send, list; then the receipt", ctx do
    ctx.owner
    |> send_json(:put, "#{ctx.base}/settings", %{
      provider: "sandbox",
      channels: ["sms"],
      quiet_start: nil,
      quiet_end: nil
    })
    |> json_response(200)

    send_body = %{
      user_id: ctx.member.id,
      template_key: "box_message",
      variables: %{text: "Αύριο κλειστά"}
    }

    assert %{"code" => "channel_contact_missing"} =
             ctx.owner
             |> send_json(:post, "#{ctx.base}/messages/preview", send_body)
             |> json_response(422)

    assert %{"contact" => %{"id" => contact_id, "phone" => "+30 •••••••678"}} =
             ctx.owner
             |> send_json(:put, "#{ctx.base}/contacts", %{
               user_id: ctx.member.id,
               phone: "691 234 5678"
             })
             |> json_response(200)

    assert %{"code" => "channel_consent_missing"} =
             ctx.owner
             |> send_json(:post, "#{ctx.base}/messages", send_body)
             |> json_response(409)

    assert %{"contact" => %{"consents" => consents}} =
             ctx.owner
             |> send_json(:put, "#{ctx.base}/contacts/#{contact_id}/consents", %{
               channel: "sms",
               purpose: "service",
               granted: true,
               text_version: "desk-v1"
             })
             |> json_response(200)

    assert Enum.any?(consents, &(&1["channel"] == "sms" and &1["purpose"] == "service" and &1["granted"]))

    assert %{"channel" => "sms", "body" => body, "segments" => 1, "estimated_cost_cents" => 7} =
             ctx.owner
             |> send_json(:post, "#{ctx.base}/messages/preview", send_body)
             |> json_response(200)

    assert body =~ "Αύριο κλειστά"

    assert %{"id" => id, "status" => "queued"} =
             ctx.owner
             |> send_json(:post, "#{ctx.base}/messages", Map.put(send_body, :idempotency_key, "click-1"))
             |> json_response(201)

    # Tests deliver inline (no Oban).
    assert %{"status" => "sent", "to" => "+30 •••••••678", "events" => [_attempt]} =
             ctx.owner |> get_json("#{ctx.base}/messages/#{id}") |> json_response(200)

    assert %{"messages" => [%{"id" => ^id}], "total" => 1} =
             ctx.owner |> get_json("#{ctx.base}/messages?status=sent") |> json_response(200)

    %{"connection" => %{"webhook_url" => url}} =
      ctx.owner |> get_json("#{ctx.base}/settings") |> json_response(200)

    path = URI.parse(url).path
    raw = Jason.encode!(%{message_id: "sbx_" <> id, status: "delivered"})

    assert %{"ok" => true} =
             build_conn()
             |> put_req_header("content-type", "application/json")
             |> put_req_header("x-palee-signature", SandboxChannel.signature(%{}, raw))
             |> post(path, raw)
             |> json_response(200)

    assert %{"status" => "delivered"} =
             ctx.owner |> get_json("#{ctx.base}/messages/#{id}") |> json_response(200)

    assert build_conn()
           |> put_req_header("content-type", "application/json")
           |> put_req_header("x-palee-signature", "bad")
           |> post(path, raw)
           |> json_response(401)

    assert %{"code" => "channel_not_retryable"} =
             ctx.owner |> send_json(:post, "#{ctx.base}/messages/#{id}/retry", %{}) |> json_response(409)
  end

  test "the member keeps their own number and consents", ctx do
    assert %{"contact" => nil, "channels" => []} =
             ctx.member_conn |> get_json(ctx.me) |> json_response(200)

    assert %{"contact" => %{"phone" => "+306912345678", "consents" => consents}} =
             ctx.member_conn
             |> send_json(:put, ctx.me, %{
               phone: "6912345678",
               locale: "en",
               text_version: "app-v1",
               consents: [%{channel: "sms", purpose: "service", granted: true}]
             })
             |> json_response(200)

    assert %{"source" => "person", "text_version" => "app-v1"} =
             Enum.find(consents, &(&1["channel"] == "sms" and &1["purpose"] == "service"))

    assert %{"code" => "validation_failed", "errors" => %{"phone" => ["invalid"]}} =
             ctx.member_conn
             |> send_json(:put, ctx.me, %{phone: "2101234567"})
             |> json_response(422)
  end
end

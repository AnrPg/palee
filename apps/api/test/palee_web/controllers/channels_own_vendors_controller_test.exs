defmodule PaleeWeb.ChannelsOwnVendorsControllerTest do
  @moduledoc """
  ADR-368/369 over HTTP: the owner connects the box's own SMTP email
  provider, checks it and removes it (the password never comes back);
  staff without `manage_settings` are refused. The Palee team sets Palee's
  margin and reads a box's monthly charge; nobody else can.
  """

  use PaleeWeb.ConnCase, async: false

  import Palee.TestFixtures

  alias Palee.Organizations

  setup %{conn: conn} do
    owner = admin_fixture(%{nickname: "ov_owner"})
    coach = user_fixture(%{nickname: "ov_coach"})
    vendor = user_fixture(%{nickname: "ov_vendor"})
    {:ok, _vendor} = Organizations.grant_vendor(vendor.id)

    {:ok, organization} =
      Organizations.create_organization(%{
        name: "Own vendors #{System.unique_integer([:positive])}"
      })

    for {user, role} <- [{owner, :owner}, {coach, :coach}] do
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
      vendor: put_bearer_token(conn, vendor),
      organization: organization,
      email: "/api/org/#{organization.slug}/admin/channels/email"
    }
  end

  defp send_json(conn, method, path, body) do
    conn
    |> recycle()
    |> put_req_header("content-type", "application/json")
    |> dispatch(@endpoint, method, path, Jason.encode!(body))
  end

  defp get_json(conn, path), do: conn |> recycle() |> get(path)

  describe "the box's own email provider (ADR-368)" do
    test "staff without manage_settings are refused", ctx do
      assert ctx.coach |> get_json(ctx.email) |> json_response(403)

      assert ctx.coach
             |> send_json(:put, ctx.email, %{host: "smtp.mailprovider.com"})
             |> json_response(403)

      assert ctx.coach |> send_json(:post, ctx.email <> "/check", %{}) |> json_response(403)
      assert ctx.coach |> recycle() |> delete(ctx.email) |> json_response(403)
    end

    test "connect, check, remove; the password never comes back", ctx do
      assert %{
               "connection" => nil,
               "ports" => [25, 465, 587, 2525],
               "tls_modes" => ["starttls", "tls"],
               "dns_guidance" => %{"domain" => nil}
             } = ctx.owner |> get_json(ctx.email) |> json_response(200)

      assert %{"code" => "email_connection_missing"} =
               ctx.owner |> send_json(:post, ctx.email <> "/check", %{}) |> json_response(404)

      body =
        ctx.owner
        |> send_json(:put, ctx.email, %{
          host: "smtp.mailprovider.com",
          port: 587,
          tls_mode: "starttls",
          username: "box@cfathina.gr",
          secret: "s3cret-smtp",
          from_address: "hello@cfathina.gr",
          from_name: "CF Αθήνα"
        })
        |> json_response(200)

      assert %{
               "connection" => %{
                 "has_secret" => true,
                 "status" => "unchecked",
                 "in_use" => false,
                 "host" => "smtp.mailprovider.com"
               },
               "dns_guidance" => %{"domain" => "cfathina.gr", "steps" => [_, _, _, _]}
             } = body

      refute Jason.encode!(body) =~ "s3cret-smtp"
      refute Map.has_key?(body["connection"], "secret")

      checked = ctx.owner |> send_json(:post, ctx.email <> "/check", %{}) |> json_response(200)

      assert %{
               "check" => %{"ok" => true},
               "connection" => %{"status" => "active", "in_use" => true}
             } =
               checked

      refute Jason.encode!(checked) =~ "s3cret-smtp"

      assert %{"errors" => _} =
               ctx.owner
               |> send_json(:put, ctx.email, %{port: 8025})
               |> json_response(422)

      assert %{"code" => "validation_failed", "errors" => %{"host" => ["invalid"]}} =
               ctx.owner
               |> send_json(:put, ctx.email, %{host: "10.0.0.8"})
               |> json_response(422)

      assert ctx.owner |> recycle() |> delete(ctx.email) |> response(204)
      assert %{"connection" => nil} = ctx.owner |> get_json(ctx.email) |> json_response(200)
    end
  end

  describe "Palee's margin (ADR-369)" do
    test "only the Palee team reads or changes margins and charges", ctx do
      path = "/api/platform/organizations/#{ctx.organization.id}/channel-charges"

      for conn <- [ctx.owner, ctx.coach] do
        assert %{"code" => "vendor_required"} =
                 conn |> get_json("/api/platform/channel-margins") |> json_response(403)

        assert %{"code" => "vendor_required"} =
                 conn
                 |> send_json(:put, "/api/platform/channel-margins", %{margins_bps: %{sms: 1}})
                 |> json_response(403)

        assert %{"code" => "vendor_required"} = conn |> get_json(path) |> json_response(403)
      end
    end

    test "the Palee team sets margins and reads a box's monthly charge", ctx do
      assert %{"margins_bps" => %{"sms" => 0, "email" => 0}} =
               ctx.vendor |> get_json("/api/platform/channel-margins") |> json_response(200)

      assert %{"margins_bps" => %{"sms" => 2500, "email" => 1000, "viber" => 0}} =
               ctx.vendor
               |> send_json(:put, "/api/platform/channel-margins", %{
                 margins_bps: %{sms: 2500, email: 1000}
               })
               |> json_response(200)

      assert ctx.vendor
             |> send_json(:put, "/api/platform/channel-margins", %{margins_bps: %{sms: -5}})
             |> json_response(422)

      assert ctx.vendor
             |> send_json(:put, "/api/platform/channel-margins", %{margins_bps: %{fax: 5}})
             |> json_response(422)

      assert %{
               "month" => "2026-11",
               "charge_cents" => 0,
               "provider_cost_cents" => 0,
               "margin_cents" => 0,
               "messages" => 0,
               "by_channel" => %{}
             } =
               ctx.vendor
               |> get_json(
                 "/api/platform/organizations/#{ctx.organization.id}/channel-charges?month=2026-11"
               )
               |> json_response(200)

      assert ctx.vendor
             |> get_json("/api/platform/organizations/#{Ecto.UUID.generate()}/channel-charges")
             |> json_response(404)

      assert ctx.vendor
             |> get_json(
               "/api/platform/organizations/#{ctx.organization.id}/channel-charges?month=2026-1"
             )
             |> json_response(422)
    end
  end
end

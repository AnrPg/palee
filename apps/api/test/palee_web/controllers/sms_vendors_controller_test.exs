defmodule PaleeWeb.SmsVendorsControllerTest do
  @moduledoc """
  ADR-396 over HTTP: the owner saves the box's own SMS vendor (the secrets
  never come back, a wrong field answers 422 with its reason), coaches are
  refused, and Yuboto's GET delivery callback reaches the box's webhook.
  """

  use PaleeWeb.ConnCase, async: false

  import Palee.TestFixtures

  alias Palee.Organizations

  setup %{conn: conn} do
    owner = admin_fixture(%{nickname: "sv_owner"})
    coach = user_fixture(%{nickname: "sv_coach"})

    {:ok, organization} =
      Organizations.create_organization(%{name: "SMS vendors #{System.unique_integer([:positive])}"})

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

    Req.Test.set_req_test_to_shared(Palee.ChannelsHttp)

    %{
      owner: put_bearer_token(conn, owner),
      coach: put_bearer_token(conn, coach),
      base: "/api/org/#{organization.slug}/admin/channels"
    }
  end

  defp put_json(conn, path, body) do
    conn
    |> recycle()
    |> put_req_header("content-type", "application/json")
    |> put(path, Jason.encode!(body))
  end

  test "coaches cannot connect a vendor", ctx do
    assert ctx.coach
           |> put_json("#{ctx.base}/settings", %{provider: "twilio", account_mode: "own"})
           |> json_response(403)
  end

  test "the owner saves a Yuboto account; the key never comes back; receipts arrive by GET",
       ctx do
    assert %{"code" => "validation_failed", "errors" => %{"secret" => ["required"]}} =
             ctx.owner
             |> put_json("#{ctx.base}/settings", %{provider: "yuboto", account_mode: "own"})
             |> json_response(422)

    Req.Test.stub(Palee.ChannelsHttp, fn conn ->
      Req.Test.json(conn, %{"ErrorCode" => 0, "currentBalance" => 50.0, "type" => "money"})
    end)

    response =
      ctx.owner
      |> put_json("#{ctx.base}/settings", %{
        provider: "yuboto",
        account_mode: "own",
        secret: "WVVCT1RPLUtFWQ==",
        sms_sender: "CFAthina"
      })
      |> json_response(200)

    assert %{"check" => %{"ok" => true}, "connection" => connection} = response
    assert connection["provider"] == "yuboto"
    assert connection["has_secret"] == true
    assert connection["has_webhook_secret"] == false
    refute Map.has_key?(connection, "secret")
    refute Jason.encode!(response) =~ "WVVCT1RPLUtFWQ"

    path = URI.parse(connection["webhook_url"]).path

    assert %{"ok" => true} =
             build_conn()
             |> get(path, %{"smsid" => "unknown", "status" => "1", "statusDescription" => "Delivered"})
             |> json_response(200)

    assert build_conn() |> get(path <> "x", %{"smsid" => "a", "status" => "1"}) |> json_response(404)
  end
end

defmodule PaleeWeb.MyFeaturesControllerTest do
  @moduledoc """
  ADR-470 over HTTP: any member of a business reads which optional features
  it has on, and the answer follows what the business set up.
  """
  use PaleeWeb.ConnCase, async: false

  import Palee.TestFixtures

  alias Palee.{Facility, Finance, Organizations}
  alias Palee.Payments.PaymentStore

  setup %{conn: conn} do
    owner = user_fixture()
    member = user_fixture()
    outsider = user_fixture()

    {:ok, organization} =
      Organizations.create_organization(%{
        name: "Features Box #{System.unique_integer([:positive])}"
      })

    join!(organization, owner, :owner)
    join!(organization, member, :member)
    {:ok, staff} = Organizations.resolve_tenant_context(owner, organization.slug)

    %{conn: conn, organization: organization, staff: staff, member: member, outsider: outsider}
  end

  defp join!(organization, user, role) do
    {:ok, _membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: user.id,
        role: role,
        status: :active,
        joined_at: DateTime.utc_now()
      })
  end

  defp features(conn, ctx, user, query \\ "") do
    conn
    |> recycle()
    |> put_bearer_token(user)
    |> get("/api/org/#{ctx.organization.slug}/me/features#{query}")
  end

  test "a new business has the optional features off", %{conn: conn} = ctx do
    body = conn |> features(ctx, ctx.member) |> json_response(200)

    for key <-
          ~w(online_payments card_autopay referrals promotions perks trials branches floor_plan) do
      assert body["features"][key] == false, "#{key} should be off"
    end

    # ADR-098: the default package modules.
    assert body["features"]["module_group_classes"] == true
  end

  test "features turn on with what the business set up", %{conn: conn} = ctx do
    {:ok, _account} =
      PaymentStore.save_account(ctx.staff, %{
        provider: "viva",
        environment: "test",
        status: "active",
        credentials: %{
          "client_id" => "c",
          "client_secret" => "s",
          "merchant_id" => "m",
          "api_key" => "k"
        },
        settings: %{"source_code" => "1234"},
        options: %{"purposes" => %{"autopay" => false}}
      })

    {:ok, _program} =
      Finance.create_referral_program(ctx.staff, %{
        name: "Φέρε φίλο",
        reward_type: "credit",
        reward_value: 500,
        active: true
      })

    {:ok, campaign} = Finance.create_promotion_campaign(ctx.staff, %{name: "Black Friday"})

    {:ok, _code} =
      Finance.create_promotion_code(ctx.staff, campaign.id, %{
        code: "BF20",
        discount_type: "percent",
        discount_value: 20
      })

    {:ok, _a} = Facility.create_location(ctx.staff, %{name: "Κυψέλη"})
    {:ok, _b} = Facility.create_location(ctx.staff, %{name: "Πατήσια"})

    features = conn |> features(ctx, ctx.member) |> json_response(200) |> Map.fetch!("features")

    assert features["online_payments"]
    assert features["online_packages"]
    refute features["card_autopay"]
    assert features["referrals"]
    assert features["promotions"]
    assert features["branches"]
  end

  test "someone outside the business does not even learn it exists", %{conn: conn} = ctx do
    assert conn |> features(ctx, ctx.outsider) |> response(404)
  end
end

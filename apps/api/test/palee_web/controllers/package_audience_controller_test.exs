defmodule PaleeWeb.PackageAudienceControllerTest do
  @moduledoc """
  ADR-553 end to end: the box chooses who sees its subscription packages
  (everyone, each person only their own, no one), a package can choose for
  itself, and people can be always shown or never shown. What someone does
  not see they cannot buy or ask for.
  """
  use PaleeWeb.ConnCase, async: false

  alias Palee.{Finance, Organizations}
  alias Palee.Application.{PublishBoxPublicProfile, UpdateBoxPublicProfile}

  import Palee.TestFixtures

  setup %{conn: conn} do
    owner = admin_fixture(%{nickname: "aud_owner"})
    member = user_fixture(%{role: :member, nickname: "aud_member"})
    stranger = user_fixture(%{role: :member, nickname: "aud_stranger"})

    {:ok, organization} =
      Organizations.create_organization(%{name: "Audience #{System.unique_integer([:positive])}"})

    add_tenant_member(organization, owner, :owner)
    add_tenant_member(organization, member, :member)
    {:ok, context} = Organizations.resolve_tenant_context(owner, organization.slug)

    {:ok, twelve} =
      Finance.create_package(context, %{
        name: "12 επισκέψεις",
        family: "visits",
        billing_period: "monthly",
        base_price_cents: 5_500
      })

    {:ok, unlimited} =
      Finance.create_package(context, %{
        name: "Unlimited",
        family: "unlimited",
        billing_period: "monthly",
        base_price_cents: 7_900
      })

    {:ok, profile} =
      UpdateBoxPublicProfile.call(context, %{"about" => "Box", "disciplines" => ["crossfit"]})

    {:ok, _profile} =
      PublishBoxPublicProfile.publish(context, %{"lock_version" => profile.lock_version})

    ctx = %{
      owner: owner,
      member: member,
      stranger: stranger,
      organization: organization,
      context: context,
      twelve: twelve,
      unlimited: unlimited
    }

    for package <- [twelve, unlimited] do
      conn
      |> put_bearer_token(owner)
      |> patch(admin_path(ctx, "/finance/packages/#{package.id}"), %{sold_online: true})
      |> json_response(200)
    end

    ctx
  end

  defp admin_path(ctx, path), do: "/api/org/#{ctx.organization.slug}/admin#{path}"

  defp names(page), do: page["packages"] |> Enum.map(& &1["name"]) |> Enum.sort()

  defp anonymous(ctx),
    do:
      build_conn()
      |> get("/api/public/boxes/#{ctx.organization.slug}/packages")
      |> json_response(200)

  defp as(ctx, user),
    do:
      build_conn()
      |> put_bearer_token(user)
      |> get("/api/boxes/#{ctx.organization.slug}/packages")
      |> json_response(200)

  defp admin(ctx, method, path, body \\ %{}) do
    build_conn()
    |> put_bearer_token(ctx.owner)
    |> dispatch(@endpoint, method, admin_path(ctx, path), body)
  end

  defp holds!(ctx, package) do
    {:ok, membership} =
      Finance.upsert_membership(ctx.context, ctx.member.id, %{
        user_type_snapshot: "member",
        status: "active",
        signup_source: "direct"
      })

    {:ok, _subscription} =
      Finance.assign_package(ctx.context, membership.id, package.id, %{
        starts_on: Date.utc_today()
      })
  end

  test "everyone sees every package by default", ctx do
    assert names(anonymous(ctx)) == ["12 επισκέψεις", "Unlimited"]
    assert %{"own_only" => false, "packages" => [%{"held" => false}, _]} = as(ctx, ctx.member)

    assert %{"audience" => "all", "exceptions" => []} =
             ctx |> admin(:get, "/package-audience") |> json_response(200)
  end

  test "«Μόνο το δικό τους»: each person sees only what they hold", ctx do
    assert %{"audience" => "own"} =
             ctx |> admin(:put, "/package-audience", %{audience: "own"}) |> json_response(200)

    assert names(anonymous(ctx)) == []

    assert %{"joining" => %{"packages" => false}} =
             build_conn()
             |> get("/api/public/boxes/#{ctx.organization.slug}")
             |> json_response(200)

    assert names(as(ctx, ctx.member)) == []

    holds!(ctx, ctx.twelve)
    page = as(ctx, ctx.member)
    assert names(page) == ["12 επισκέψεις"]
    assert page["own_only"] == true
    assert [%{"held" => true}] = page["packages"]

    # What the member does not see they cannot ask for at the desk.
    build_conn()
    |> put_bearer_token(ctx.member)
    |> post("/api/org/#{ctx.organization.slug}/me/packages/#{ctx.unlimited.id}/request")
    |> json_response(409)
    |> then(&assert(&1["code"] == "package_not_for_sale"))
  end

  test "a package's own choice wins over the box's", ctx do
    admin(ctx, :put, "/package-audience", %{audience: "none"})

    assert %{"audience" => "all"} =
             ctx
             |> admin(:put, "/package-audience/packages/#{ctx.unlimited.id}", %{audience: "all"})
             |> json_response(200)

    assert names(anonymous(ctx)) == ["Unlimited"]

    ctx
    |> admin(:put, "/package-audience/packages/#{ctx.unlimited.id}", %{audience: nil})
    |> json_response(200)

    assert names(anonymous(ctx)) == []
  end

  test "people the box always shows or never shows", ctx do
    admin(ctx, :put, "/package-audience", %{audience: "none"})

    settings =
      ctx
      |> admin(:post, "/package-audience/exceptions", %{
        user_id: ctx.stranger.id,
        package_id: ctx.unlimited.id,
        effect: "show"
      })
      |> json_response(200)

    assert [%{"effect" => "show", "person" => %{"nickname" => "aud_stranger"}} = shown] =
             settings["exceptions"]

    assert names(as(ctx, ctx.stranger)) == ["Unlimited"]
    assert %{"own_only" => false} = as(ctx, ctx.stranger)
    assert names(as(ctx, ctx.member)) == []
    assert names(anonymous(ctx)) == []

    # A box-wide «hide» for the same person loses to the package's «show».
    ctx
    |> admin(:post, "/package-audience/exceptions", %{user_id: ctx.stranger.id, effect: "hide"})
    |> json_response(200)

    assert names(as(ctx, ctx.stranger)) == ["Unlimited"]

    # The same person and package again changes the exception, never doubles it.
    ctx
    |> admin(:post, "/package-audience/exceptions", %{
      user_id: ctx.stranger.id,
      package_id: ctx.unlimited.id,
      effect: "hide"
    })
    |> json_response(200)
    |> then(&assert(length(&1["exceptions"]) == 2))

    assert names(as(ctx, ctx.stranger)) == []

    assert %{"exceptions" => [_one]} =
             ctx
             |> admin(:delete, "/package-audience/exceptions/#{shown["id"]}")
             |> json_response(200)
  end

  test "a hidden person cannot buy, whatever the box shows others", ctx do
    holds!(ctx, ctx.twelve)

    ctx
    |> admin(:post, "/package-audience/exceptions", %{user_id: ctx.member.id, effect: "hide"})
    |> json_response(200)

    assert names(as(ctx, ctx.member)) == []
    assert names(anonymous(ctx)) == ["12 επισκέψεις", "Unlimited"]

    build_conn()
    |> put_bearer_token(ctx.member)
    |> get("/api/org/#{ctx.organization.slug}/me/packages/#{ctx.twelve.id}/purchase-terms")
    |> json_response(409)
  end

  test "choices are checked", ctx do
    ctx |> admin(:put, "/package-audience", %{audience: "some"}) |> json_response(422)

    ctx
    |> admin(:post, "/package-audience/exceptions", %{user_id: ctx.member.id, effect: "maybe"})
    |> json_response(422)

    ctx
    |> admin(:post, "/package-audience/exceptions", %{
      user_id: Ecto.UUID.generate(),
      effect: "hide"
    })
    |> json_response(404)

    ctx
    |> admin(:delete, "/package-audience/exceptions/#{Ecto.UUID.generate()}")
    |> json_response(404)
  end

  test "a box member without package rights cannot change it", ctx do
    build_conn()
    |> put_bearer_token(ctx.member)
    |> put(admin_path(ctx, "/package-audience"), %{audience: "none"})
    |> json_response(403)
  end

  defp add_tenant_member(organization, user, role) do
    {:ok, membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: user.id,
        role: role,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    membership
  end
end

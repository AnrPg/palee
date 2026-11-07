defmodule PaleeWeb.JoinBoxControllerTest do
  @moduledoc """
  ADR-552: becoming a box member without the member join link. Buying a
  package the box lists to everyone admits the person; anyone else asks
  («Ζήτα να γίνεις μέλος») and the staff accept or decline.
  """

  use PaleeWeb.ConnCase, async: false

  import Palee.TestFixtures

  alias Palee.{Finance, Notifications, Organizations}
  alias Palee.Application.{PublishBoxPublicProfile, UpdateBoxPublicProfile}

  setup do
    start_supervised!(
      {Oban, Keyword.put(Application.fetch_env!(:palee, Oban), :testing, :manual)}
    )

    owner = admin_fixture(%{nickname: "join_owner"})
    coach = user_fixture(%{nickname: "join_coach"})
    visitor = user_fixture(%{nickname: "join_visitor"})

    {:ok, organization} =
      Organizations.create_organization(%{name: "Join Box #{System.unique_integer([:positive])}"})

    add_tenant_member(organization, owner, :owner)
    add_tenant_member(organization, coach, :coach)
    {:ok, context} = Organizations.resolve_tenant_context(owner, organization.slug)

    {:ok, package} =
      Finance.create_package(context, %{
        name: "Μηνιαίο",
        family: "unlimited",
        billing_period: "monthly",
        base_price_cents: 6_000
      })

    {:ok, profile} =
      UpdateBoxPublicProfile.call(context, %{"about" => "Box", "disciplines" => ["crossfit"]})

    {:ok, _profile} =
      PublishBoxPublicProfile.publish(context, %{"lock_version" => profile.lock_version})

    %{
      owner: owner,
      coach: coach,
      visitor: visitor,
      organization: organization,
      package: package,
      slug: organization.slug
    }
  end

  defp as(user), do: build_conn() |> put_bearer_token(user)

  defp standing(ctx, user), do: Organizations.membership_standing(ctx.organization.id, user.id)

  defp drain, do: Oban.drain_queue(queue: :notifications, with_safety: false)

  defp types(user), do: user.id |> Notifications.list_for_user() |> Enum.map(& &1.type)

  describe "buying makes you a box member" do
    test "a listed package admits the person while the join link is off", ctx do
      # The join link is off (the default): `/join/<slug>` refuses.
      assert ctx.visitor
             |> as()
             |> post("/api/memberships/join/#{ctx.slug}")
             |> json_response(404)

      assert %{"role" => "member", "organization" => %{"slug" => slug}} =
               ctx.visitor
               |> as()
               |> post("/api/memberships/join/#{ctx.slug}/package/#{ctx.package.id}")
               |> json_response(201)

      assert slug == ctx.slug
      assert standing(ctx, ctx.visitor) == :member

      # Again: already a member.
      assert ctx.visitor
             |> as()
             |> post("/api/memberships/join/#{ctx.slug}/package/#{ctx.package.id}")
             |> json_response(200)
    end

    test "a package the box does not list admits no one", ctx do
      ctx.owner
      |> as()
      |> patch("/api/org/#{ctx.slug}/admin/finance/packages/#{ctx.package.id}", %{
        sold_online: false
      })
      |> json_response(200)

      assert %{"code" => "package_not_for_sale"} =
               ctx.visitor
               |> as()
               |> post("/api/memberships/join/#{ctx.slug}/package/#{ctx.package.id}")
               |> json_response(409)

      assert standing(ctx, ctx.visitor) == :none
    end

    test "a former member is not let back in by buying", ctx do
      {:ok, membership} =
        Organizations.add_membership(%{
          organization_id: ctx.organization.id,
          user_id: ctx.visitor.id,
          role: :member,
          status: :revoked,
          joined_at: DateTime.utc_now()
        })

      assert membership.status == :revoked

      assert %{"code" => "membership_unavailable"} =
               ctx.visitor
               |> as()
               |> post("/api/memberships/join/#{ctx.slug}/package/#{ctx.package.id}")
               |> json_response(409)
    end
  end

  describe "«Ζήτα να γίνεις μέλος»" do
    test "the person asks, the staff hear and accept, the person becomes a box member", ctx do
      path = "/api/boxes/#{ctx.slug}/join-request"

      assert %{"request" => nil} = ctx.visitor |> as() |> get(path) |> json_response(200)

      assert %{"request" => %{"id" => id, "status" => "requested", "box" => %{"slug" => _}}} =
               ctx.visitor |> as() |> post(path) |> json_response(201)

      # Asking again returns the open request.
      assert %{"request" => %{"id" => ^id}} =
               ctx.visitor |> as() |> post(path) |> json_response(201)

      drain()
      assert "join_requested" in types(ctx.owner)
      # Coaches do not manage memberships.
      refute "join_requested" in types(ctx.coach)

      admin = "/api/org/#{ctx.slug}/admin/join-requests"

      assert %{"requests" => [%{"id" => ^id, "person" => %{"nickname" => _}}]} =
               ctx.owner |> as() |> get(admin) |> json_response(200)

      assert ctx.coach |> as() |> get(admin) |> json_response(403)

      assert %{"request" => %{"status" => "accepted"}} =
               ctx.owner |> as() |> post("#{admin}/#{id}/accept") |> json_response(200)

      assert standing(ctx, ctx.visitor) == :member
      assert %{"requests" => []} = ctx.owner |> as() |> get(admin) |> json_response(200)

      # Answered once only.
      assert %{"code" => "join_request_closed"} =
               ctx.owner |> as() |> post("#{admin}/#{id}/decline") |> json_response(409)

      drain()
      assert "join_request_accepted" in types(ctx.visitor)

      # A box member does not ask.
      assert %{"code" => "already_member"} =
               ctx.visitor |> as() |> post(path) |> json_response(409)
    end

    test "a declined request tells the person and admits no one", ctx do
      path = "/api/boxes/#{ctx.slug}/join-request"

      %{"request" => %{"id" => id}} = ctx.visitor |> as() |> post(path) |> json_response(201)

      assert %{"request" => %{"status" => "declined"}} =
               ctx.owner
               |> as()
               |> post("/api/org/#{ctx.slug}/admin/join-requests/#{id}/decline")
               |> json_response(200)

      assert standing(ctx, ctx.visitor) == :none

      assert %{"request" => %{"status" => "declined"}} =
               ctx.visitor |> as() |> get(path) |> json_response(200)

      drain()
      assert "join_request_declined" in types(ctx.visitor)

      # They may ask again.
      assert %{"request" => %{"status" => "requested"}} =
               ctx.visitor |> as() |> post(path) |> json_response(201)
    end

    test "the person withdraws their request", ctx do
      path = "/api/boxes/#{ctx.slug}/join-request"
      ctx.visitor |> as() |> post(path) |> json_response(201)

      assert %{"request" => %{"status" => "cancelled"}} =
               ctx.visitor |> as() |> post("#{path}/cancel") |> json_response(200)

      assert ctx.visitor |> as() |> post("#{path}/cancel") |> json_response(404)

      assert %{"requests" => []} =
               ctx.owner
               |> as()
               |> get("/api/org/#{ctx.slug}/admin/join-requests")
               |> json_response(200)
    end

    test "accepting lets a former member back in", ctx do
      {:ok, _membership} =
        Organizations.add_membership(%{
          organization_id: ctx.organization.id,
          user_id: ctx.visitor.id,
          role: :member,
          status: :revoked,
          joined_at: DateTime.utc_now()
        })

      %{"request" => %{"id" => id}} =
        ctx.visitor |> as() |> post("/api/boxes/#{ctx.slug}/join-request") |> json_response(201)

      ctx.owner
      |> as()
      |> post("/api/org/#{ctx.slug}/admin/join-requests/#{id}/accept")
      |> json_response(200)

      assert standing(ctx, ctx.visitor) == :member
    end

    test "an unknown or unpublished box answers 404", ctx do
      assert ctx.visitor
             |> as()
             |> post("/api/boxes/nope-#{ctx.slug}/join-request")
             |> json_response(404)
    end
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

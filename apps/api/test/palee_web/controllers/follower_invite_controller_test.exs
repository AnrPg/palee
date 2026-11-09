defmodule PaleeWeb.FollowerInviteControllerTest do
  @moduledoc """
  ADR-580: a box invites the people who follow it to become box members,
  one at a time or many at once; the person sees it on the box page, as a
  notification and as a message from the box, and may say «Όχι, ευχαριστώ».
  """

  use PaleeWeb.ConnCase, async: false

  import Palee.TestFixtures

  alias Palee.{Finance, Notifications, Organizations, Repo}
  alias Palee.Application.{PublishBoxPublicProfile, UpdateBoxPublicProfile}
  alias Palee.Organizations.Domain.FollowerInvitePolicy

  setup do
    start_supervised!(
      {Oban, Keyword.put(Application.fetch_env!(:palee, Oban), :testing, :manual)}
    )

    owner = admin_fixture(%{nickname: "invite_owner"})
    coach = user_fixture(%{nickname: "invite_coach"})
    fan = user_fixture(%{nickname: "invite_fan"})
    other_fan = user_fixture(%{nickname: "invite_other_fan"})
    member = user_fixture(%{nickname: "invite_member"})

    {:ok, organization} =
      Organizations.create_organization(%{
        name: "Invite Box #{System.unique_integer([:positive])}"
      })

    add_tenant_member(organization, owner, :owner)
    add_tenant_member(organization, coach, :coach)
    add_tenant_member(organization, member, :member)
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

    for person <- [fan, other_fan, member], do: follow(person, organization)

    %{
      owner: owner,
      coach: coach,
      fan: fan,
      other_fan: other_fan,
      member: member,
      organization: organization,
      package: package,
      slug: organization.slug
    }
  end

  defp as(user), do: build_conn() |> put_bearer_token(user)

  defp follow(user, organization) do
    user
    |> as()
    |> post("/api/me/follows", %{target_type: "organization", target_id: organization.id})
    |> json_response(200)
  end

  defp list(ctx, query \\ "") do
    ctx.owner
    |> as()
    |> get("/api/org/#{ctx.slug}/admin/follower-invites#{query}")
    |> json_response(200)
  end

  defp ids(%{"followers" => followers}), do: Enum.map(followers, & &1["person"]["id"])

  defp invite(ctx, body, user \\ nil) do
    (user || ctx.owner)
    |> as()
    |> post("/api/org/#{ctx.slug}/admin/follower-invites", body)
  end

  defp drain do
    for queue <- [:default, :notifications, :notifications],
        do: Oban.drain_queue(queue: queue, with_safety: false)
  end

  defp types(user), do: user.id |> Notifications.list_for_user() |> Enum.map(& &1.type)

  describe "the staff list" do
    test "lists followers who are not box members, never box members", ctx do
      page = list(ctx)

      assert Enum.sort(ids(page)) == Enum.sort([ctx.fan.id, ctx.other_fan.id])
      refute ctx.member.id in ids(page)
      assert page["counts"] == %{"listed" => 2, "invitable" => 2, "trial" => 0, "former" => 0}
      assert %{"packages" => [%{"id" => package_id}], "trial_available" => false} = page["offer"]
      assert package_id == ctx.package.id

      assert %{"counts" => %{"invitable" => 2}} =
               ctx.owner
               |> as()
               |> get("/api/org/#{ctx.slug}/admin/follower-invites/summary")
               |> json_response(200)
    end

    test "tags former box members and filters by them", ctx do
      {:ok, _membership} =
        Organizations.add_membership(%{
          organization_id: ctx.organization.id,
          user_id: ctx.fan.id,
          role: :member,
          status: :revoked,
          joined_at: DateTime.utc_now()
        })

      page = list(ctx, "?filter=former")
      assert ids(page) == [ctx.fan.id]
      assert [%{"former_member" => true}] = page["followers"]
      assert page["counts"]["former"] == 1
    end

    test "leaves out people who turned box invitations off", ctx do
      assert %{"box_invites" => false} =
               ctx.fan
               |> as()
               |> put("/api/me/social/privacy", %{box_invites: false})
               |> json_response(200)

      assert ids(list(ctx)) == [ctx.other_fan.id]
    end

    test "leaves out people whose join request is open", ctx do
      ctx.fan |> as() |> post("/api/boxes/#{ctx.slug}/join-request") |> json_response(201)
      assert ids(list(ctx)) == [ctx.other_fan.id]
    end

    test "is for the staff who manage memberships", ctx do
      ctx.coach
      |> as()
      |> get("/api/org/#{ctx.slug}/admin/follower-invites")
      |> json_response(403)

      assert invite(ctx, %{user_ids: [ctx.fan.id]}, ctx.coach) |> json_response(403)
    end

    test "refuses an unknown filter", ctx do
      assert %{"code" => "invalid_follower_filter"} =
               ctx.owner
               |> as()
               |> get("/api/org/#{ctx.slug}/admin/follower-invites?filter=nope")
               |> json_response(422)
    end
  end

  describe "inviting" do
    test "one person: a notification, a quiet message from the box, the box page", ctx do
      assert %{"sent" => 1, "skipped" => []} =
               invite(ctx, %{
                 user_ids: [ctx.fan.id],
                 message: "Έλα να προπονηθούμε μαζί!",
                 package_id: ctx.package.id
               })
               |> json_response(201)

      drain()
      assert "follower_invited" in types(ctx.fan)
      refute "box_message" in types(ctx.fan)

      assert %{"conversations" => [conversation]} =
               ctx.fan |> as() |> get("/api/me/box-conversations") |> json_response(200)

      assert conversation["last_message"]["body"] =~ "Έλα να προπονηθούμε μαζί!"

      assert %{
               "invite" => %{
                 "message" => "Έλα να προπονηθούμε μαζί!",
                 "offer_trial" => false,
                 "package" => %{"id" => package_id, "name" => "Μηνιαίο"},
                 "box" => %{"slug" => slug}
               }
             } =
               ctx.fan
               |> as()
               |> get("/api/boxes/#{ctx.slug}/follower-invite")
               |> json_response(200)

      assert package_id == ctx.package.id
      assert slug == ctx.slug

      # In the list: «Εστάλη», not invitable for 90 days.
      [row] = Enum.filter(list(ctx)["followers"], &(&1["person"]["id"] == ctx.fan.id))
      assert %{"invitable" => false, "invite" => %{"status" => "sent"}} = row
    end

    test "many at once; the same person only again after 90 days", ctx do
      assert %{"sent" => 2} =
               invite(ctx, %{user_ids: [ctx.fan.id, ctx.other_fan.id]}) |> json_response(201)

      assert %{"sent" => 0, "skipped" => skipped} =
               invite(ctx, %{user_ids: [ctx.fan.id, ctx.member.id]}) |> json_response(201)

      assert Enum.sort_by(skipped, & &1["reason"]) == [
               %{"user_id" => ctx.member.id, "reason" => "not_a_follower"},
               %{"user_id" => ctx.fan.id, "reason" => "recently_invited"}
             ]

      # 90 days later the box may invite again.
      days = FollowerInvitePolicy.reinvite_after_days()

      Repo.query!(
        "UPDATE organization_follower_invites SET inserted_at = inserted_at - make_interval(days => $1)",
        [days]
      )

      assert %{"sent" => 1} = invite(ctx, %{user_ids: [ctx.fan.id]}) |> json_response(201)
    end

    test "«Όχι, ευχαριστώ» stops further invitations from the box", ctx do
      invite(ctx, %{user_ids: [ctx.fan.id]}) |> json_response(201)

      assert %{"invite" => nil} =
               ctx.fan
               |> as()
               |> post("/api/boxes/#{ctx.slug}/follower-invite/decline")
               |> json_response(200)

      assert %{"invite" => nil} =
               ctx.fan
               |> as()
               |> get("/api/boxes/#{ctx.slug}/follower-invite")
               |> json_response(200)

      Repo.query!(
        "UPDATE organization_follower_invites SET inserted_at = inserted_at - interval '400 days'"
      )

      assert %{"sent" => 0, "skipped" => [%{"reason" => "declined"}]} =
               invite(ctx, %{user_ids: [ctx.fan.id]}) |> json_response(201)

      [row] = Enum.filter(list(ctx)["followers"], &(&1["person"]["id"] == ctx.fan.id))
      assert %{"invitable" => false, "invite" => %{"status" => "declined"}} = row
    end

    test "a package the box does not list to everyone, or a trial it does not take", ctx do
      ctx.owner
      |> as()
      |> patch("/api/org/#{ctx.slug}/admin/finance/packages/#{ctx.package.id}", %{
        sold_online: false
      })
      |> json_response(200)

      assert %{"code" => "package_not_for_sale"} =
               invite(ctx, %{user_ids: [ctx.fan.id], package_id: ctx.package.id})
               |> json_response(409)

      assert %{"code" => "trials_closed"} =
               invite(ctx, %{user_ids: [ctx.fan.id], offer_trial: true}) |> json_response(422)
    end

    test "the invitation disappears once the person is a box member", ctx do
      invite(ctx, %{user_ids: [ctx.fan.id]}) |> json_response(201)

      ctx.fan
      |> as()
      |> post("/api/memberships/join/#{ctx.slug}/package/#{ctx.package.id}")
      |> json_response(201)

      assert %{"invite" => nil} =
               ctx.fan
               |> as()
               |> get("/api/boxes/#{ctx.slug}/follower-invite")
               |> json_response(200)

      refute ctx.fan.id in ids(list(ctx))
    end

    test "a message over 500 characters is refused", ctx do
      assert invite(ctx, %{user_ids: [ctx.fan.id], message: String.duplicate("α", 501)})
             |> json_response(422)
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

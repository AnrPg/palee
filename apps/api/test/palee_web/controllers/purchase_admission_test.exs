defmodule PaleeWeb.PurchaseAdmissionTest do
  @moduledoc """
  ADR-642 end to end: starting to buy a package gives the person no role
  anyone sees (not a member, not a guest, and the box's staff do not see
  them); «Το θέλω» makes them a member (their one class while it waits); a
  package keeps them one; a request that closes with no package takes them
  back to nothing. Every screen reads the same answer.
  """

  use PaleeWeb.ConnCase, async: false

  import Palee.TestFixtures

  alias Palee.{Finance, Organizations}
  alias Palee.Application.{PublishBoxPublicProfile, UpdateBoxPublicProfile}

  setup do
    start_supervised!(
      {Oban, Keyword.put(Application.fetch_env!(:palee, Oban), :testing, :manual)}
    )

    owner = admin_fixture(%{nickname: "admission_owner"})
    visitor = user_fixture(%{nickname: "admission_visitor"})

    {:ok, organization} =
      Organizations.create_organization(%{
        name: "Admission Box #{System.unique_integer([:positive])}"
      })

    add_tenant_member(organization, owner, :owner)
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

    %{owner: owner, visitor: visitor, organization: organization, package: package}
  end

  defp as(user), do: build_conn() |> put_bearer_token(user)
  defp slug(ctx), do: ctx.organization.slug

  defp start_buying(ctx) do
    ctx.visitor
    |> as()
    |> post("/api/memberships/join/#{slug(ctx)}/package/#{ctx.package.id}")
  end

  defp ask(ctx) do
    ctx.visitor
    |> as()
    |> post("/api/org/#{slug(ctx)}/me/packages/#{ctx.package.id}/request", %{})
    |> json_response(201)
    |> get_in(["request", "id"])
  end

  defp admin(ctx, path, body),
    do: ctx.owner |> as() |> post("/api/org/#{slug(ctx)}/admin#{path}", body)

  defp row(ctx),
    do:
      Palee.Repo.get_by!(Palee.Organizations.OrganizationMembership,
        organization_id: ctx.organization.id,
        user_id: ctx.visitor.id
      )

  # What «Βρες» and Συνδέσεις › Boxes say (ADR-638).
  defp my_join(ctx) do
    ctx.visitor
    |> as()
    |> get("/api/box-search?q=#{URI.encode_www_form(ctx.organization.name)}")
    |> json_response(200)
    |> Map.fetch!("boxes")
    |> Enum.find(&(&1["organization_id"] == ctx.organization.id))
    |> Map.fetch!("my_join")
  end

  # The account's boxes (the member app, «Box»).
  defp my_boxes(ctx) do
    ctx.visitor
    |> as()
    |> get("/api/memberships")
    |> json_response(200)
    |> Enum.map(& &1["organization"]["slug"])
  end

  defp guest_boxes(ctx) do
    ctx.visitor
    |> as()
    |> get("/api/memberships/guest-boxes")
    |> json_response(200)
    |> Map.fetch!("boxes")
  end

  # Who the box's staff see: the directory and the desk's people search.
  defp staff_see?(ctx) do
    users =
      ctx.owner
      |> as()
      |> get("/api/org/#{slug(ctx)}/admin/users")
      |> json_response(200)
      |> Map.fetch!("users")

    people =
      ctx.owner
      |> as()
      |> get("/api/org/#{slug(ctx)}/admin/payments/desk/people?q=admission_visitor")
      |> json_response(200)
      |> Map.fetch!("people")
      |> Enum.filter(&(&1["relation"] != "none"))

    in_directory = Enum.any?(users, &(&1["id"] == ctx.visitor.id))
    at_desk = Enum.any?(people, &(&1["user_id"] == ctx.visitor.id))

    assert in_directory == at_desk,
           "staff see inconsistent things: #{inspect({in_directory, at_desk})}"

    in_directory
  end

  test "starting to buy gives no role anyone sees", ctx do
    assert %{"organization" => %{"slug" => _slug}} = start_buying(ctx) |> json_response(201)

    assert row(ctx).roles == [:guest]
    assert %DateTime{} = row(ctx).purchase_admission_at
    assert my_join(ctx) == "none"
    refute slug(ctx) in my_boxes(ctx)
    # Not a desk guest either: no «Είσαι επισκέπτης» banner.
    assert guest_boxes(ctx) == []
    # The box's staff do not see them anywhere.
    refute staff_see?(ctx)

    # Pressing «Συνέχεια» again changes nothing.
    assert start_buying(ctx) |> json_response(200)
    assert row(ctx).roles == [:guest]
  end

  test "«Το θέλω» makes a member who sees the box; a decline makes a guest again", ctx do
    start_buying(ctx) |> json_response(201)
    request_id = ask(ctx)

    assert row(ctx).roles == [:member]
    assert %DateTime{} = row(ctx).purchase_admission_at
    assert my_join(ctx) == "member"
    assert slug(ctx) in my_boxes(ctx)
    assert staff_see?(ctx)

    admin(ctx, "/finance/package-requests/#{request_id}/decline", %{reason: "Γεμάτο"})
    |> json_response(200)

    assert row(ctx).roles == [:guest]
    assert my_join(ctx) == "none"
    refute slug(ctx) in my_boxes(ctx)
    assert guest_boxes(ctx) == []
    refute staff_see?(ctx)

    # They may try again.
    ask(ctx)
    assert row(ctx).roles == [:member]
  end

  test "taking the request back makes a guest again", ctx do
    start_buying(ctx) |> json_response(201)
    request_id = ask(ctx)

    ctx.visitor
    |> as()
    |> post("/api/org/#{slug(ctx)}/me/package-requests/#{request_id}/cancel", %{})
    |> json_response(200)

    assert row(ctx).roles == [:guest]
    assert my_join(ctx) == "none"
  end

  test "front desk making them a guest makes a real guest the staff see", ctx do
    start_buying(ctx) |> json_response(201)
    refute staff_see?(ctx)

    admin(ctx, "/payments/desk/guests", %{user_id: ctx.visitor.id})
    |> json_response(201)

    assert row(ctx).roles == [:guest]
    assert row(ctx).purchase_admission_at == nil
    assert [_box] = guest_boxes(ctx)
    assert staff_see?(ctx)
  end

  test "a package makes them a member for good", ctx do
    start_buying(ctx) |> json_response(201)
    request_id = ask(ctx)

    admin(ctx, "/finance/package-requests/#{request_id}/collect", %{payment_method: "cash"})
    |> json_response(200)

    assert row(ctx).roles == [:member]
    assert row(ctx).purchase_admission_at == nil
    assert my_join(ctx) == "member"
  end

  test "online: nothing until the payment goes through, then a member", ctx do
    ctx.owner
    |> as()
    |> patch("/api/org/#{slug(ctx)}/admin/finance/packages/#{ctx.package.id}", %{
      sold_online: true
    })
    |> json_response(200)

    ctx.owner
    |> as()
    |> put("/api/org/#{slug(ctx)}/admin/payments/account", %{
      provider: "sandbox",
      environment: "test"
    })
    |> json_response(200)

    start_buying(ctx) |> json_response(201)

    payment =
      ctx.visitor
      |> as()
      |> post("/api/org/#{slug(ctx)}/me/packages/#{ctx.package.id}/buy", %{
        idempotency_key: "admission-buy-1",
        start_now: true,
        language: "el"
      })
      |> json_response(200)
      |> Map.fetch!("payment")

    # The provider's page is open, nothing paid: still nothing anyone sees.
    assert row(ctx).roles == [:guest]
    assert my_join(ctx) == "none"
    refute staff_see?(ctx)

    ref = URI.decode_query(URI.parse(payment["redirect_url"]).query)["sandbox_checkout"]

    assert %{"payment" => %{"status" => "succeeded"}} =
             ctx.visitor
             |> as()
             |> post("/api/org/#{slug(ctx)}/me/payments/sandbox/complete", %{
               provider_ref: ref,
               outcome: "succeeded"
             })
             |> json_response(200)

    assert row(ctx).roles == [:member]
    assert row(ctx).purchase_admission_at == nil
    assert my_join(ctx) == "member"
    assert slug(ctx) in my_boxes(ctx)
  end

  test "someone who joined another way is never made a guest", ctx do
    add_tenant_member(ctx.organization, ctx.visitor, :member)
    request_id = ask(ctx)

    admin(ctx, "/finance/package-requests/#{request_id}/decline", %{reason: "Όχι τώρα"})
    |> json_response(200)

    assert row(ctx).roles == [:member]
    assert my_join(ctx) == "member"
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

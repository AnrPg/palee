defmodule PaleeWeb.ProgrammesControllerTest do
  @moduledoc """
  ADR-370/371 end to end with the sandbox provider: a box writes a
  programme from its WODs, publishes it (frozen copies), lists it in the
  catalogue; a buyer pays on the provider page, gets the WODs on dated days
  and the sale in Finance with its lineage; reviews, withdrawal and staff
  refunds; another business never sees it.
  """
  use PaleeWeb.ConnCase, async: false

  import Ecto.Query
  import Palee.TestFixtures

  alias Palee.{AnalyticsHelpers, Organizations, Payments, Repo}
  alias Palee.Application.{PublishBoxPublicProfile, UpdateBoxPublicProfile}
  alias Palee.Application.Programmes.Sweep
  alias Palee.Infrastructure.Tenancy.RepoContext

  setup %{conn: conn} do
    owner = admin_fixture(%{nickname: "prog_owner"})
    buyer = user_fixture(%{role: :member, nickname: "prog_buyer"})

    {:ok, organization} =
      Organizations.create_organization(%{
        name: "Programme Box #{System.unique_integer([:positive])}"
      })

    AnalyticsHelpers.add_membership(organization, owner, :owner)
    AnalyticsHelpers.add_membership(organization, buyer, :member)
    {:ok, context} = Organizations.resolve_tenant_context(owner, organization.slug)
    first = workout_fixture(owner, %{tenant_context: context, title: "Engine A"})
    second = workout_fixture(owner, %{tenant_context: context, title: "Engine B"})

    %{
      owner: owner,
      buyer: buyer,
      organization: organization,
      context: context,
      first: first,
      second: second,
      as: fn user -> put_bearer_token(conn, user) end,
      admin: "/api/org/#{organization.slug}/admin",
      me: "/api/org/#{organization.slug}/me"
    }
  end

  defp create_published(ctx, attrs \\ %{}) do
    programme =
      ctx.as.(ctx.owner)
      |> post(
        ctx.admin <> "/programmes",
        Map.merge(
          %{
            title: "Engine 2 weeks",
            summary: "Two weeks of engine work",
            price_cents: 4_000,
            listing: "marketplace",
            preview_days: 1,
            draft_weeks: 2,
            draft_days: [
              %{day: 0, workout_id: ctx.first.id},
              %{day: 2, workout_id: ctx.second.id},
              %{day: 9, workout_id: ctx.first.id}
            ]
          },
          attrs
        )
      )
      |> json_response(201)
      |> Map.fetch!("programme")

    assert programme["status"] == "draft"

    ctx.as.(ctx.owner)
    |> post(ctx.admin <> "/programmes/#{programme["id"]}/publish", %{changelog: "First"})
    |> json_response(200)
    |> Map.fetch!("programme")
  end

  defp connect_sandbox(ctx) do
    ctx.as.(ctx.owner)
    |> put(ctx.admin <> "/payments/account", %{provider: "sandbox", environment: "test"})
    |> json_response(200)
  end

  defp buy(ctx, programme, key) do
    result =
      ctx.as.(ctx.buyer)
      |> post(ctx.me <> "/programmes/#{programme["id"]}/buy", %{
        idempotency_key: key,
        start_now: true,
        language: "el"
      })
      |> json_response(200)

    ref = URI.decode_query(URI.parse(result["payment"]["redirect_url"]).query)["sandbox_checkout"]

    paid =
      ctx.as.(ctx.buyer)
      |> post(ctx.me <> "/payments/sandbox/complete", %{provider_ref: ref, outcome: "succeeded"})
      |> json_response(200)
      |> Map.fetch!("payment")

    {result["purchase_id"], paid}
  end

  test "publishing freezes the WODs as hidden copies and versions the days", ctx do
    programme = create_published(ctx)

    assert programme["status"] == "published"
    assert %{"number" => 1, "weeks" => 2, "days" => days} = programme["version"]
    assert length(days) == 3
    frozen = days |> Enum.map(& &1["workout_id"]) |> Enum.uniq()
    assert length(frozen) == 2
    refute ctx.first.id in frozen
    assert Enum.all?(days, &(&1["source_workout_id"] in [ctx.first.id, ctx.second.id]))

    # A second publication is version 2; buyers of version 1 keep theirs.
    ctx.as.(ctx.owner)
    |> patch(ctx.admin <> "/programmes/#{programme["id"]}", %{
      draft_days: [%{day: 0, workout_id: ctx.second.id}]
    })
    |> json_response(200)

    again =
      ctx.as.(ctx.owner)
      |> post(ctx.admin <> "/programmes/#{programme["id"]}/publish", %{})
      |> json_response(200)

    assert again["programme"]["version"]["number"] == 2
  end

  test "drafts only take this box's published WODs", ctx do
    ctx.as.(ctx.owner)
    |> post(ctx.admin <> "/programmes", %{
      title: "Bad",
      draft_days: [%{day: 0, workout_id: Ecto.UUID.generate()}]
    })
    |> json_response(422)
    |> then(&assert(&1["code"] == "programme_workout_unavailable"))

    ctx.as.(ctx.owner)
    |> post(ctx.admin <> "/programmes", %{
      title: "Free",
      draft_days: [%{day: 0, workout_id: ctx.first.id}]
    })
    |> json_response(201)
    |> then(fn %{"programme" => p} ->
      ctx.as.(ctx.owner)
      |> post(ctx.admin <> "/programmes/#{p["id"]}/publish", %{})
      |> json_response(422)
      |> then(&assert(&1["code"] == "programme_price_required"))
    end)
  end

  test "the catalogue and the box page show public fields and the preview only", ctx do
    programme = create_published(ctx)

    catalogue = public_conn() |> get("/api/public/programmes?query=Engine") |> json_response(200)
    assert Enum.any?(catalogue["programmes"], &(&1["id"] == programme["id"] and &1["weeks"] == 2))

    # Wildcards are literal: "%" matches nothing.
    assert %{"programmes" => []} =
             public_conn() |> get("/api/public/programmes?query=%25%25") |> json_response(200)

    box_only = create_published(ctx, %{title: "Box only", listing: "box"})
    catalogue = public_conn() |> get("/api/public/programmes") |> json_response(200)
    refute Enum.any?(catalogue["programmes"], &(&1["id"] == box_only["id"]))
  end

  # ADR-530 §3: the website's «Προγράμματα» lists what the box sells.
  test "the box website lists the programmes for sale with a link to each", ctx do
    programme = create_published(ctx)
    publish_page(ctx)

    site =
      public_conn()
      |> get("/api/public/sites/#{ctx.organization.slug}")
      |> json_response(200)

    assert "programmes" in site["sections"]

    assert [
             %{"id" => id, "title" => "Engine 2 weeks", "weeks" => 2, "price_cents" => 4_000} =
               listed
           ] =
             site["programmes"]

    assert id == programme["id"]
    assert String.ends_with?(listed["url"], "/b/#{ctx.organization.slug}/programmes/#{id}")
  end

  test "buying: checkout, WODs on dated days, Finance lineage, review, withdrawal", ctx do
    programme = create_published(ctx)
    connect_sandbox(ctx)

    terms =
      ctx.as.(ctx.buyer)
      |> get(ctx.me <> "/programmes/#{programme["id"]}/purchase-terms?language=el")
      |> json_response(200)

    assert terms["available"]
    assert terms["withdrawal_days"] == 14
    assert terms["refund_rule"] == "before_start"

    ctx.as.(ctx.buyer)
    |> post(ctx.me <> "/programmes/#{programme["id"]}/buy", %{idempotency_key: "prog-buy-0"})
    |> json_response(422)
    |> then(&assert(&1["code"] == "programme_start_consent_required"))

    {purchase_id, paid} = buy(ctx, programme, "prog-buy-1")
    assert paid["status"] == "succeeded"
    assert paid["fulfilment_status"] == "done"
    assert paid["purpose_type"] == "programme"

    mine =
      ctx.as.(ctx.buyer)
      |> get(ctx.me <> "/programme-purchases/#{purchase_id}")
      |> json_response(200)

    assert mine["purchase"]["status"] == "active"
    assert length(mine["purchase"]["days"]) == 3
    today = Organizations.local_today(ctx.organization.id)
    assert hd(mine["purchase"]["days"])["date"] == Date.to_iso8601(today)

    deliveries =
      RepoContext.run(ctx.context, fn ->
        Repo.all(
          from d in "programme_deliveries",
            where: d.purchase_id == type(^purchase_id, :binary_id),
            select: d.scheduled_for
        )
      end)

    assert length(deliveries) == 3

    links =
      RepoContext.run(ctx.context, fn ->
        Repo.all(
          from l in "assigned_workout_athletes",
            where: l.athlete_id == type(^ctx.buyer.id, :binary_id),
            select: l.scheduled_for
        )
      end)

    assert length(links) == 3

    # A retried fulfilment never schedules or records twice.
    Payments.process(ctx.context, :due, DateTime.utc_now())

    lineage =
      RepoContext.run(ctx.context, fn ->
        Repo.all(
          from p in "membership_payments",
            where:
              p.source_type == "programme_purchase" and
                p.source_id == type(^purchase_id, :binary_id),
            select: {p.revenue_stream, p.payment_method, p.amount_cents}
        )
      end)

    assert lineage == [{"other", "online", 4_000}]

    # Buying it again while active is refused.
    ctx.as.(ctx.buyer)
    |> post(ctx.me <> "/programmes/#{programme["id"]}/buy", %{
      idempotency_key: "prog-buy-2",
      start_now: true
    })
    |> json_response(409)
    |> then(&assert(&1["code"] == "programme_already_owned"))

    review =
      ctx.as.(ctx.buyer)
      |> post(ctx.me <> "/programme-purchases/#{purchase_id}/review", %{
        rating: 5,
        body: "Great engine work"
      })
      |> json_response(200)

    assert review["review"]["version_number"] == 1

    publish_page(ctx)

    public =
      public_conn()
      |> get("/api/public/boxes/#{ctx.organization.slug}/programmes/#{programme["id"]}")
      |> json_response(200)

    assert public["programme"]["reviews"] == %{"average" => 5.0, "count" => 1}
    assert [%{"day" => 0, "title" => "Engine A"}] = public["programme"]["preview"]
    refute Map.has_key?(public["programme"], "days")

    # The seller hides it with a reason; it leaves the averages.
    ctx.as.(ctx.owner)
    |> post(ctx.admin <> "/programme-reviews/#{review["review"]["id"]}/moderate", %{
      hidden_reason: "off_topic"
    })
    |> json_response(200)

    public =
      public_conn()
      |> get("/api/public/boxes/#{ctx.organization.slug}/programmes/#{programme["id"]}")
      |> json_response(200)

    assert public["programme"]["reviews"]["count"] == 0

    # Withdrawal on day one: everything back, future WODs gone.
    withdrawal =
      ctx.as.(ctx.buyer)
      |> post(ctx.me <> "/programme-purchases/#{purchase_id}/withdraw")
      |> json_response(200)

    assert withdrawal["purchase"]["status"] == "withdrawn"
    assert withdrawal["purchase"]["refunded_cents"] == 4_000
    assert withdrawal["rule"] in ["withdrawal", "before_start"]

    left =
      RepoContext.run(ctx.context, fn ->
        Repo.all(
          from l in "assigned_workout_athletes",
            where: l.athlete_id == type(^ctx.buyer.id, :binary_id),
            select: l.id
        )
      end)

    assert left == []

    reversals =
      RepoContext.run(ctx.context, fn ->
        Repo.all(
          from r in "finance_payment_reversals",
            where: r.source_type == "programme_purchase",
            select: {r.revenue_stream, r.amount_cents}
        )
      end)

    assert reversals == [{"other", 4_000}]

    sales =
      ctx.as.(ctx.owner)
      |> get(ctx.admin <> "/programmes/#{programme["id"]}/purchases")
      |> json_response(200)

    assert [%{"status" => "withdrawn", "buyer" => %{"nickname" => "prog_buyer"}}] =
             sales["purchases"]
  end

  test "staff refund part of a purchase, then the rest", ctx do
    programme = create_published(ctx)
    connect_sandbox(ctx)
    {purchase_id, _paid} = buy(ctx, programme, "prog-buy-staff")

    partial =
      ctx.as.(ctx.owner)
      |> post(ctx.admin <> "/programme-purchases/#{purchase_id}/refund", %{
        amount_cents: 1_000,
        idempotency_key: "refund-part-1"
      })
      |> json_response(200)

    assert partial["purchase"]["status"] == "active"
    assert partial["purchase"]["refunded_cents"] == 1_000

    ctx.as.(ctx.owner)
    |> post(ctx.admin <> "/programme-purchases/#{purchase_id}/refund", %{
      amount_cents: 3_001,
      idempotency_key: "refund-part-2"
    })
    |> json_response(422)
    |> then(&assert(&1["code"] == "refund_exceeds_remaining"))

    full =
      ctx.as.(ctx.owner)
      |> post(ctx.admin <> "/programme-purchases/#{purchase_id}/refund", %{
        amount_cents: 3_000,
        idempotency_key: "refund-part-3"
      })
      |> json_response(200)

    assert full["purchase"]["status"] == "refunded"
  end

  test "the hourly sweep completes ended purchases and closes abandoned checkouts", ctx do
    programme = create_published(ctx)
    connect_sandbox(ctx)
    {purchase_id, _paid} = buy(ctx, programme, "prog-sweep-1")
    now = DateTime.utc_now()

    # Still running: nothing changes.
    assert %{completed: 0, cancelled: 0} = Sweep.sweep(ctx.context, now)

    yesterday = Date.add(Organizations.local_today(ctx.organization.id, now), -1)
    set_purchase(ctx, purchase_id, ends_on: yesterday, starts_on: Date.add(yesterday, -13))

    assert %{completed: 1} = Sweep.sweep(ctx.context, now)
    assert purchase_status(ctx, purchase_id) == "completed"
    # A second run changes nothing.
    assert %{completed: 0} = Sweep.sweep(ctx.context, now)

    # A checkout opened two days ago and never paid.
    second = create_published(ctx, %{title: "Engine again"})

    pending =
      ctx.as.(ctx.buyer)
      |> post(ctx.me <> "/programmes/#{second["id"]}/buy", %{
        idempotency_key: "prog-sweep-2",
        start_now: true
      })
      |> json_response(200)
      |> Map.fetch!("purchase_id")

    set_purchase(ctx, pending, inserted_at: DateTime.add(now, -2, :day))

    # The payment page is still open: a late payment must still find it.
    assert %{cancelled: 0} = Sweep.sweep(ctx.context, now)
    assert purchase_status(ctx, pending) == "pending_payment"

    intent_id =
      RepoContext.run(ctx.context, fn ->
        Repo.one(
          from p in "programme_purchases",
            where: p.id == type(^pending, :binary_id),
            select: type(p.payment_intent_id, :binary_id)
        )
      end)

    RepoContext.run(ctx.context, fn ->
      Repo.update_all(
        from(i in "payment_intents", where: i.id == type(^intent_id, :binary_id)),
        set: [status: "expired"]
      )
    end)

    assert %{cancelled: 1} = Sweep.sweep(ctx.context, now)
    assert purchase_status(ctx, pending) == "cancelled"
  end

  defp set_purchase(ctx, id, changes) do
    RepoContext.run(ctx.context, fn ->
      Repo.update_all(
        from(p in "programme_purchases", where: p.id == type(^id, :binary_id)),
        set: changes
      )
    end)
  end

  defp purchase_status(ctx, id) do
    RepoContext.run(ctx.context, fn ->
      Repo.one(
        from p in "programme_purchases",
          where: p.id == type(^id, :binary_id),
          select: p.status
      )
    end)
  end

  test "a buyer cannot reach staff routes and another box never sees the programme", ctx do
    programme = create_published(ctx)

    ctx.as.(ctx.buyer) |> get(ctx.admin <> "/programmes") |> json_response(403)

    other_owner = admin_fixture(%{nickname: "other_owner"})

    {:ok, other} =
      Organizations.create_organization(%{
        name: "Other Box #{System.unique_integer([:positive])}"
      })

    AnalyticsHelpers.add_membership(other, other_owner, :owner)

    ctx.as.(other_owner)
    |> get("/api/org/#{other.slug}/admin/programmes/#{programme["id"]}")
    |> json_response(404)

    {:ok, other_context} = Organizations.resolve_tenant_context(other_owner, other.slug)
    assert Palee.Programmes.list_programmes(other_context) == []
  end

  defp publish_page(ctx) do
    {:ok, profile} =
      UpdateBoxPublicProfile.call(ctx.context, %{
        "about" => "A box that sells programmes",
        "disciplines" => ["crossfit"]
      })

    {:ok, _profile} =
      PublishBoxPublicProfile.publish(ctx.context, %{"lock_version" => profile.lock_version})
  end

  defp public_conn, do: put_req_header(build_conn(), "content-type", "application/json")
end

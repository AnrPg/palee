defmodule PaleeWeb.CardSurchargeControllerTest do
  @moduledoc """
  ADR-340 (CP-A5) end to end: the owner's card surcharge is refused where
  the law forbids it, shown before paying, added only to a card the law
  allows it on (a saved card online, a card on the box's own machine at the
  desk) and recorded as revenue of the sale on its own Finance row.
  """
  use PaleeWeb.ConnCase, async: false

  alias Palee.{Finance, Fiscal, Organizations, Payments}
  alias Palee.Application.Payments.OnlinePayments

  import Palee.TestFixtures

  @greek %{
    legal_name: "CrossFit Αθήνα ΙΚΕ",
    country_code: "GR",
    tax_id: "090000045",
    tax_office: "Α' Αθηνών",
    street: "Ερμού",
    postal_code: "10563",
    city: "Αθήνα"
  }

  @american %{
    legal_name: "Brooklyn Barbell LLC",
    country_code: "US",
    street: "Atlantic Ave",
    building_number: "100",
    postal_code: "11201",
    city: "Brooklyn",
    region: "NY"
  }

  setup do
    admin = admin_fixture(%{nickname: "fee_admin"})
    member = user_fixture(%{role: :member, nickname: "fee_member"})
    {organization, context} = tenant_fixture(admin, "Fee Tenant")
    add_tenant_member(organization, member, :member)

    {:ok, membership} =
      Finance.upsert_membership(context, member.id, %{
        user_type_snapshot: "member",
        status: "active",
        signup_source: "admin_created"
      })

    %{
      admin: admin,
      member: member,
      organization: organization,
      context: context,
      membership: membership
    }
  end

  defp admin_path(ctx, path), do: "/api/org/#{ctx.organization.slug}/admin#{path}"
  defp me_path(ctx, path), do: "/api/org/#{ctx.organization.slug}/me#{path}"
  defp as(conn, user), do: put_bearer_token(conn, user)

  defp identity(ctx, identity) do
    {:ok, _identity} = Fiscal.save_identity(ctx.context, identity, ctx.admin.id, DateTime.utc_now())
  end

  defp open_invoice(ctx, cents) do
    {:ok, invoice} =
      Finance.create_invoice(ctx.context, ctx.membership.id, %{
        amount_cents: cents,
        description: "Μηνιαία συνδρομή",
        due_date: Date.add(Date.utc_today(), -1)
      })

    {:ok, invoice} = Finance.issue_invoice(ctx.context, invoice.id, %{})
    invoice
  end

  defp put_surcharge(conn, ctx, body),
    do: conn |> as(ctx.admin) |> put(admin_path(ctx, "/payments/surcharge"), body)

  test "a box with no known country cannot pass the fee on", %{conn: conn} = ctx do
    status = conn |> as(ctx.admin) |> get(admin_path(ctx, "/payments/surcharge")) |> json_response(200)
    assert status["settings"]["enabled"] == false
    assert status["allowed"] == false
    assert status["law"]["rule"] == "none"

    body =
      conn
      |> put_surcharge(ctx, %{enabled: true, channels: ["desk"], percent_bps: 150})
      |> json_response(422)

    assert body["code"] == "card_surcharge_not_allowed"
  end

  test "Greece: only a commercial or non-EEA card at the desk, on the receipt", %{conn: conn} = ctx do
    identity(ctx, @greek)

    status = conn |> as(ctx.admin) |> get(admin_path(ctx, "/payments/surcharge")) |> json_response(200)
    assert status["law"]["rule"] == "eea_non_consumer"
    assert status["law"]["sources"] != []

    assert %{"errors" => %{"at_cost_confirmed" => ["required"]}} =
             conn
             |> put_surcharge(ctx, %{enabled: true, channels: ["desk"], percent_bps: 150})
             |> json_response(422)

    saved =
      conn
      |> put_surcharge(ctx, %{
        enabled: true,
        channels: ["desk"],
        percent_bps: 150,
        at_cost_confirmed: true
      })
      |> json_response(200)

    assert saved["settings"]["enabled"] and saved["saved"]

    quote =
      conn
      |> as(ctx.admin)
      |> post(admin_path(ctx, "/payments/surcharge/quote"), %{
        channel: "desk",
        amount_cents: 6_000,
        card: %{funding: "credit", country: "GR", commercial: false}
      })
      |> json_response(200)

    assert quote["applies"] == false and quote["reason"] == "card_not_surchargeable"

    # A package sale, so the receipt knows the sale's tax category.
    {:ok, package} =
      Finance.create_package(ctx.context, %{
        name: "Unlimited",
        family: "unlimited",
        billing_period: "monthly",
        base_price_cents: 6_000
      })

    {:ok, subscription} =
      Finance.assign_package(ctx.context, ctx.membership.id, package.id, %{})

    receive = admin_path(ctx, "/finance/members/#{ctx.member.id}/payments/receive")

    refused =
      conn
      |> as(ctx.admin)
      |> post(receive, %{
        amount_cents: 6_000,
        payment_method: "card_manual",
        membership_package_subscription_id: subscription.id,
        paid_on: Date.to_iso8601(Date.utc_today()),
        surcharge_cents: 90,
        card: %{funding: "credit", country: "GR", commercial: false},
        idempotency_key: Ecto.UUID.generate()
      })
      |> json_response(422)

    assert refused["code"] == "card_surcharge_not_allowed"

    received =
      conn
      |> as(ctx.admin)
      |> post(receive, %{
        amount_cents: 6_000,
        payment_method: "card_manual",
        membership_package_subscription_id: subscription.id,
        paid_on: Date.to_iso8601(Date.utc_today()),
        surcharge_cents: 90,
        card: %{funding: "credit", country: "GR", commercial: true},
        idempotency_key: Ecto.UUID.generate()
      })
      |> json_response(201)
      |> Map.fetch!("received")

    payment_id = received["payment"]["id"]

    assert %{payments: [surcharge]} =
             Finance.revenue_lineage(ctx.context, "card_surcharge", payment_id)

    assert surcharge.amount_cents == 90
    assert surcharge.payment_method == "card_manual"

    # The surcharge is on the sale's receipt, as revenue.
    assert received["fiscal_document"]["gross_cents"] == 6_090
  end

  test "US: a saved credit card carries the fee online, a new card never", %{conn: conn} = ctx do
    identity(ctx, @american)

    conn
    |> as(ctx.admin)
    |> put(admin_path(ctx, "/payments/account"), %{provider: "sandbox", environment: "test"})
    |> json_response(200)

    # Above the Visa US cap of 3 %: refused.
    assert %{"code" => "card_surcharge_not_allowed"} =
             conn
             |> put_surcharge(ctx, %{enabled: true, channels: ["online"], percent_bps: 400})
             |> json_response(422)

    saved =
      conn
      |> put_surcharge(ctx, %{enabled: true, channels: ["online"], percent_bps: 250})
      |> json_response(200)

    assert saved["settings"]["region_code"] == "US-NY"
    assert saved["law"]["rule"] == "credit_only"

    invoice = open_invoice(ctx, 6_000)

    terms =
      conn
      |> as(ctx.member)
      |> get(me_path(ctx, "/invoices/#{invoice.id}/payment-terms"))
      |> json_response(200)

    assert terms["surcharge"]["applies"] == false
    assert terms["surcharge"]["reason"] == "card_unknown"

    # Pay with a new card and keep it (the sandbox card is credit).
    payment =
      conn
      |> as(ctx.member)
      |> post(me_path(ctx, "/invoices/#{invoice.id}/pay"), %{
        save_card: true,
        consent_accepted: true,
        autopay: true,
        idempotency_key: Ecto.UUID.generate()
      })
      |> json_response(200)
      |> Map.fetch!("payment")

    assert payment["surcharge_cents"] == 0
    ref = URI.decode_query(URI.parse(payment["redirect_url"]).query)["sandbox_checkout"]

    conn
    |> as(ctx.member)
    |> post(me_path(ctx, "/payments/sandbox/complete"), %{provider_ref: ref, outcome: "succeeded"})
    |> json_response(200)

    [method] = Payments.methods(ctx.context, ctx.member.id)
    assert method.card_funding == "credit"

    quote =
      conn
      |> as(ctx.member)
      |> get(me_path(ctx, "/payments/surcharge-quote?amount_cents=5000&payment_method_id=#{method.id}"))
      |> json_response(200)

    assert quote["applies"] and quote["surcharge_cents"] == 125 and quote["total_cents"] == 5_125

    # The next bill is paid with the saved card, fee included, recorded apart.
    next = open_invoice(ctx, 5_000)
    assert OnlinePayments.autopay(%{organization_id: ctx.organization.id}) == 1

    {:ok, next} = Finance.get_invoice(ctx.context, next.id)
    assert next.status == "paid"

    %{payments: payments} = Payments.list(ctx.context, %{})
    charged = Enum.find(payments, &(&1.purpose_id == next.id))
    assert charged.surcharge_cents == 125 and charged.amount_cents == 5_000

    assert %{payments: [surcharge]} =
             Finance.revenue_lineage(ctx.context, "card_surcharge", charged.id)

    assert surcharge.amount_cents == 125
    assert surcharge.payment_method == "online"
  end

  defp tenant_fixture(user, name) do
    {:ok, organization} =
      Organizations.create_organization(%{name: "#{name} #{System.unique_integer([:positive])}"})

    add_tenant_member(organization, user, :owner)
    {:ok, context} = Organizations.resolve_tenant_context(user, organization.slug)
    {organization, context}
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

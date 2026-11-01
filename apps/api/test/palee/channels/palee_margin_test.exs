defmodule Palee.Channels.PaleeMarginTest do
  @moduledoc """
  ADR-369 under Row Level Security: Palee's margin (a platform setting) on
  messages sent on Palee's own provider account. The box sees and is
  charged the provider's price plus the margin, its budget cap compares
  that price, and the month's charge is kept for billing with the
  providers' cost beside it (Palee team only). Own-account messages carry
  no margin and no Palee charge.
  """

  use Palee.DataCase, async: false

  @moduletag :rls_enforced

  import Palee.AnalyticsHelpers, only: [organization_fixture: 0, member_context: 1]

  alias Palee.Channels
  alias Palee.Channels.Domain.CostPolicy
  alias Palee.Application.Channels.{ChannelMargins, ChannelMessages, SendThroughChannel}
  alias Palee.Infrastructure.Channels.SandboxChannel

  @noon ~U[2026-11-10 10:00:00.000000Z]

  setup do
    {organization, owner, context} = bypass_rls(fn -> organization_fixture() end)
    {member, _member_context} = bypass_rls(fn -> member_context(organization) end)
    env = %{now: @noon, time_zone: "Europe/Athens", box_name: "CF Αθήνα"}

    {:ok, contact} =
      Channels.save_contact(context, {:user, member.id}, %{phone: "6912345678"}, "GR")

    {:ok, _} =
      Channels.set_consent(
        context,
        contact.id,
        %{channel: "sms", purpose: "service", granted: true, source: "person", text_version: "v1"},
        member.id,
        @noon
      )

    %{organization: organization, owner: owner, context: context, member: member, env: env}
  end

  defp connect(ctx, attrs \\ %{}) do
    {:ok, connection} =
      Channels.save_connection(
        ctx.context,
        Map.merge(%{provider: "sandbox", channels: ["sms"], monthly_budget_cents: 2000}, attrs),
        ctx.owner.id
      )

    connection
  end

  defp request(ctx) do
    %{
      person: {:user, ctx.member.id},
      template_key: "class_cancelled",
      variables: %{"class" => "WOD", "when" => "Τρι 18:00"},
      idempotency_key: "k-#{System.unique_integer([:positive])}",
      source: "automation"
    }
  end

  test "the margin is 0 until the Palee team sets it, and only known channels take one", ctx do
    assert %{margins_bps: %{"sms" => 0, "email" => 0, "viber" => 0, "whatsapp" => 0}} =
             ChannelMargins.show()

    assert {:ok, %{margins_bps: %{"sms" => 2500, "email" => 0}}} =
             ChannelMargins.save(%{margins_bps: %{sms: 2500}}, ctx.owner.id)

    # Channels not sent keep theirs.
    assert {:ok, %{margins_bps: %{"sms" => 2500, "email" => 1000}}} =
             ChannelMargins.save(%{"margins_bps" => %{"email" => 1000}}, ctx.owner.id)

    assert {:error, {:invalid_fields, %{"fax" => "invalid"}}} =
             ChannelMargins.save(%{margins_bps: %{fax: 10}}, ctx.owner.id)
  end

  test "on Palee's account the box sees and pays the provider's price plus the margin", ctx do
    {:ok, _} = Channels.save_margins(%{"sms" => 2500}, ctx.owner.id)
    connect(ctx)

    {:ok, plan} = Channels.preview(ctx.context, request(ctx), ctx.env)
    assert plan.margin_bps == 2500
    assert plan.estimated_cost_cents == CostPolicy.price(plan.provider_cost_cents, 2500)
    assert plan.estimated_cost_cents > plan.provider_cost_cents

    # The box-facing preview carries the box's price only.
    {:ok, shown} =
      SendThroughChannel.preview(ctx.context, %{
        "user_id" => ctx.member.id,
        "template_key" => "class_cancelled",
        "variables" => %{"class" => "WOD", "when" => "Τρι 18:00"}
      })

    assert shown.estimated_cost_cents == plan.estimated_cost_cents
    refute Map.has_key?(shown, :provider_cost_cents)
    refute Map.has_key?(shown, :margin_bps)

    {:ok, message} = Channels.send(ctx.context, request(ctx), ctx.env)
    assert message.provider_cost_cents == plan.provider_cost_cents
    assert message.margin_bps == 2500
    assert {:ok, %{sent: 1}} = Channels.deliver(ctx.context, :due, @noon)

    # The provider says what it charged: the box's price follows it.
    connection = Channels.connection(ctx.context)
    token = connection |> Channels.public_connection() |> Map.fetch!(:webhook_url) |> Path.basename()

    params = %{"message_id" => "sbx_" <> message.id, "status" => "delivered", "cost_cents" => 10}
    raw = Jason.encode!(params)

    assert {:ok, %{receipts: 1}} =
             Channels.handle_webhook(
               %{organization_id: ctx.organization.id},
               token,
               %{
                 params: params,
                 raw_body: raw,
                 headers: [{"x-palee-signature", SandboxChannel.signature(%{}, raw)}]
               },
               @noon
             )

    # 10 × 1.25 = 12.5, rounded up.
    assert {:ok, %{cost_cents: 13, estimated_cost_cents: estimate}} =
             ChannelMessages.show(ctx.context, message.id)

    assert estimate == plan.estimated_cost_cents

    assert {:ok, %{spent_cents: 13, palee_charge_cents: 13}} =
             Channels.usage(ctx.context, nil, ctx.env)

    assert {:ok, charge} = ChannelMargins.monthly_charge(ctx.organization.id, "2026-11", @noon)

    assert %{
             month: "2026-11",
             charge_cents: 13,
             provider_cost_cents: 10,
             margin_cents: 3,
             messages: 1,
             by_channel: %{"sms" => %{charge_cents: 13, provider_cost_cents: 10, count: 1}}
           } = charge

    assert {:ok, %{charge_cents: 0, messages: 0}} =
             ChannelMargins.monthly_charge(ctx.organization.id, "2026-10", @noon)

    assert {:error, :not_found} = ChannelMargins.monthly_charge(Ecto.UUID.generate(), nil, @noon)
    assert {:error, :not_found} = ChannelMargins.monthly_charge("nope", nil, @noon)
  end

  test "the monthly budget cap compares the box's price, not the provider's", ctx do
    {:ok, _} = Channels.save_margins(%{"sms" => 5000}, ctx.owner.id)
    connect(ctx)
    {:ok, plan} = Channels.preview(ctx.context, request(ctx), ctx.env)

    # A cap the provider's price fits under but the box's price does not.
    connect(ctx, %{monthly_budget_cents: plan.estimated_cost_cents - 1})
    assert plan.provider_cost_cents <= plan.estimated_cost_cents - 1

    assert {:error, :channel_budget_exceeded} =
             Channels.send(ctx.context, request(ctx), ctx.env)
  end

  test "the box's own account carries no margin and no Palee charge", ctx do
    {:ok, _} = Channels.save_margins(%{"sms" => 2500}, ctx.owner.id)
    connect(ctx, %{account_mode: "own"})

    {:ok, message} = Channels.send(ctx.context, request(ctx), ctx.env)
    assert message.margin_bps == 0
    assert message.estimated_cost_cents == message.provider_cost_cents

    assert {:ok, %{spent_cents: spent, palee_charge_cents: 0}} =
             Channels.usage(ctx.context, nil, ctx.env)

    assert spent == message.estimated_cost_cents

    assert {:ok, %{charge_cents: 0, provider_cost_cents: 0, messages: 0}} =
             ChannelMargins.monthly_charge(ctx.organization.id, "2026-11", @noon)
  end

  test "a margin set later does not change messages already queued", ctx do
    connect(ctx)
    {:ok, before} = Channels.send(ctx.context, request(ctx), ctx.env)
    assert before.margin_bps == 0

    {:ok, _} = Channels.save_margins(%{"sms" => 10_000}, ctx.owner.id)
    {:ok, later} = Channels.send(ctx.context, request(ctx), ctx.env)
    assert later.estimated_cost_cents == 2 * before.estimated_cost_cents

    assert {:ok, %{spent_cents: spent}} = Channels.usage(ctx.context, nil, ctx.env)
    assert spent == before.estimated_cost_cents + later.estimated_cost_cents
  end
end

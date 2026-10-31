defmodule Palee.Channels.Domain.CostAndDeliveryTest do
  use ExUnit.Case, async: true

  alias Palee.Channels.Domain.{CostPolicy, DeliveryPolicy, Templates}

  @now ~U[2026-11-10 10:00:00.000000Z]

  test "the estimate is the price per part times the parts" do
    assert CostPolicy.estimate(nil, "sms", "service", "GR", 2) == 14
    assert CostPolicy.estimate(nil, "sms", "service", nil, 1) == 9

    assert CostPolicy.estimate(%{{"sms", "service"} => %{default: 5}}, "sms", "service", "GR", 3) ==
             15
  end

  test "the budget cap counts what is already spent" do
    assert :ok = CostPolicy.within_budget(1990, 7, 2000)
    assert {:error, :channel_budget_exceeded} = CostPolicy.within_budget(1995, 7, 2000)
    assert {:error, :channel_budget_exceeded} = CostPolicy.within_budget(0, 7, 0)
  end

  test "the month runs on the box's clock" do
    # 23:30 UTC on 31 October is already November in Athens.
    {from, to} = CostPolicy.month_range(~U[2026-10-31 23:30:00Z], "Europe/Athens")
    assert from == ~U[2026-10-31 22:00:00Z]
    assert to == ~U[2026-11-30 22:00:00Z]
    assert {:error, :invalid_month} = CostPolicy.month_range_of("2026-13", "Europe/Athens")
  end

  test "a provider outage retries with growing waits, then fails" do
    message = %{attempts: 1}
    changes = DeliveryPolicy.outcome(message, {:error, {:transient, :timeout}}, @now)
    assert changes.status == "queued"
    assert changes.next_attempt_at == DateTime.add(@now, 60, :second)

    assert %{status: "failed", error_code: "provider_unavailable"} =
             DeliveryPolicy.outcome(%{attempts: 5}, {:error, {:transient, :x}}, @now)
  end

  test "a refused or uncertain call is never sent again by itself" do
    assert %{status: "failed", error_code: "provider_rejected"} =
             DeliveryPolicy.outcome(%{attempts: 1}, {:error, {:rejected, "bad"}}, @now)

    assert %{status: "failed", error_code: "delivery_uncertain"} =
             DeliveryPolicy.outcome(%{attempts: 1}, {:error, {:uncertain, "timeout"}}, @now)
  end

  test "accepted calls keep the provider id and the charged price" do
    assert %{status: "sent", provider_message_id: "m1", cost_cents: 6} =
             DeliveryPolicy.outcome(
               %{attempts: 1},
               {:ok, %{provider_message_id: "m1", cost_cents: 6, currency: "EUR"}},
               @now
             )
  end

  test "receipts arrive out of order: final states stay final" do
    assert %{status: "delivered"} =
             DeliveryPolicy.receipt(%{status: "sent"}, %{status: "delivered"}, @now)

    assert nil == DeliveryPolicy.receipt(%{status: "delivered"}, %{status: "failed"}, @now)
    assert nil == DeliveryPolicy.receipt(%{status: "sent"}, %{status: "sent"}, @now)

    assert %{status: "failed", error_code: "hard_bounce"} =
             DeliveryPolicy.receipt(
               %{status: "sent"},
               %{status: "failed", error_code: "hard_bounce"},
               @now
             )
  end

  test "templates: the box's wording, then Palee's, then English; no empty gaps" do
    assert {:ok, {"Hi {{text}}", "el"}} =
             Templates.body("box_message", "el", %{"el" => "Hi {{text}}"})

    assert {:ok, {_body, "en"}} = Templates.body("class_cancelled", "de", %{})
    assert {:error, :channel_template_missing} = Templates.body("nope", "el", %{})

    assert {:ok, "Box: Το WOD"} =
             Templates.render("{{box}}: {{text}}", %{"box" => "Box", "text" => "Το WOD"})

    assert {:error, {:invalid_fields, %{variables: "missing_text"}}} =
             Templates.render("{{box}}: {{text}}", %{"box" => "Box", "text" => "  "})
  end
end

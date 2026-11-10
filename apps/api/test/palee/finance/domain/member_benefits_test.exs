defmodule Palee.Finance.Domain.MemberBenefitsTest do
  # ADR-612: what «Δώρο ή χάρη» accepts and how a grant reads today.
  use ExUnit.Case, async: true

  alias Palee.Finance.Domain.MemberBenefits

  @today ~D[2026-11-10]

  defp validate(params), do: MemberBenefits.validate_grant(params, @today)

  test "a grace and free access need a last day that has not passed" do
    assert {:error, :benefit_end_required} = validate(%{"kind" => "grace"})

    assert {:error, :benefit_ends_in_past} =
             validate(%{"kind" => "free_access", "ends_on" => "2026-11-09"})

    assert {:ok, %{"kind" => "grace", "ends_on" => ~D[2026-11-10]}} =
             validate(%{"kind" => "grace", "ends_on" => "2026-11-10"})
  end

  test "extra uses need what, how many and for how long" do
    base = %{"kind" => "extra_uses", "allowance" => "class_visits", "quantity" => 1}

    assert {:error, :benefit_period_required} = validate(base)
    assert {:error, :invalid_benefit_quantity} = validate(%{base | "quantity" => 0})

    assert {:ok, %{"period" => "calendar_month"}} =
             validate(Map.put(base, "period", "calendar_month"))
  end

  test "a package needs free this period or a price" do
    base = %{"kind" => "package", "package_id" => Ecto.UUID.generate()}

    assert {:error, :benefit_pricing_required} = validate(base)

    assert {:ok, %{"pricing" => "this_period_free"}} =
             validate(Map.put(base, "pricing", %{"mode" => "this_period_free"}))

    assert {:ok, %{"pricing" => "price", "price_cents" => 0}} =
             validate(Map.put(base, "pricing", %{"mode" => "price", "price_cents" => 0}))

    assert {:error, :benefit_pricing_required} =
             validate(Map.put(base, "pricing", %{"mode" => "price", "price_cents" => -1}))
  end

  test "a forgiven debt names its charges" do
    assert {:error, :benefit_invoices_required} =
             validate(%{"kind" => "debt_forgiven", "invoice_ids" => []})

    assert {:error, :invalid_benefit_invoice} =
             validate(%{"kind" => "debt_forgiven", "invoice_ids" => ["nope"]})
  end

  test "the reason is optional and at most 500 characters; unknown kinds are refused" do
    assert {:error, :invalid_benefit_kind} = validate(%{"kind" => "voucher"})

    assert {:error, :benefit_reason_too_long} =
             validate(%{
               "kind" => "grace",
               "ends_on" => "2026-11-20",
               "reason" => String.duplicate("x", 501)
             })

    assert {:ok, %{"reason" => nil}} =
             validate(%{"kind" => "grace", "ends_on" => "2026-11-20", "reason" => "  "})
  end

  test "access takes the latest-ending free access over a grace" do
    grants = [
      %{id: "a", kind: "grace", starts_on: ~D[2026-11-01], ends_on: ~D[2026-11-30]},
      %{id: "b", kind: "free_access", starts_on: ~D[2026-11-01], ends_on: ~D[2026-11-15]}
    ]

    assert %{kind: _kind, until: %Date{}} = MemberBenefits.access(grants, [], @today)
    assert MemberBenefits.access([], [], @today) == nil
  end

  test "a grant's state follows its dates and its revocation" do
    grant = %{action: "grant", kind: "grace", starts_on: ~D[2026-11-01], ends_on: ~D[2026-11-20]}

    assert MemberBenefits.state(grant, false, @today) == "active"
    assert MemberBenefits.state(grant, true, @today) == "revoked"
    assert MemberBenefits.state(%{grant | ends_on: ~D[2026-11-09]}, false, @today) == "ended"
    assert MemberBenefits.state(%{grant | starts_on: ~D[2026-11-11]}, false, @today) == "upcoming"
    assert MemberBenefits.state(%{grant | kind: "package"}, false, @today) == "given"
  end
end

defmodule Palee.Finance.Domain.PackageStartTest do
  # ADR-795: what a package that waited for the first session tells the member.
  use ExUnit.Case, async: true

  alias Palee.Finance.Domain.PackageStart

  @visits "group_classes.visits"

  defp bought(attrs \\ %{}) do
    Map.merge(
      %{
        name: "Unlimited",
        price_cents: 5000,
        billing_period: "monthly",
        params: %{
          "entitlement_version" => 2,
          "package_type" => "membership",
          "fields" => %{
            "group_classes.included" => true,
            @visits => %{"limit" => 12, "period" => "calendar_month"}
          }
        }
      },
      attrs
    )
  end

  test "waits only in first_session mode, without a fixed start" do
    assert PackageStart.waits?("first_session", %{})
    refute PackageStart.waits?("first_session", %{"starts_on" => "2026-11-28"})
    refute PackageStart.waits?("payment", %{})
  end

  test "nothing changed: no changes" do
    assert PackageStart.changes(bought(), bought()) == []
  end

  test "a price rise is important, a price cut a warning" do
    assert [%{key: "price", severity: "important"}] =
             PackageStart.changes(bought(), bought(%{price_cents: 6000}))

    assert [%{key: "price", severity: "warning"}] =
             PackageStart.changes(bought(), bought(%{price_cents: 4000}))
  end

  test "fewer benefits are serious, more a warning" do
    fewer =
      bought(%{
        params: %{
          "entitlement_version" => 2,
          "package_type" => "membership",
          "fields" => %{
            "group_classes.included" => true,
            @visits => %{"limit" => 8, "period" => "calendar_month"}
          }
        }
      })

    more =
      bought(%{
        params: %{
          "entitlement_version" => 2,
          "package_type" => "membership",
          "fields" => %{
            "group_classes.included" => true,
            @visits => %{"limit" => 16, "period" => "calendar_month"}
          }
        }
      })

    assert [%{key: @visits, severity: "serious"}] = PackageStart.changes(bought(), fewer)
    assert [%{key: @visits, severity: "warning"}] = PackageStart.changes(bought(), more)
  end

  test "a new name is a warning and the highest severity names the review" do
    changes = PackageStart.changes(bought(), bought(%{name: "Unlimited Plus", price_cents: 6000}))
    assert [%{key: "name", severity: "warning"}, %{key: "price"}] = changes
    assert PackageStart.overall(changes) == "important"
    assert PackageStart.overall([]) == nil
  end

  test "the started package takes the fields; the price waits for the next payment" do
    fewer =
      bought(%{
        price_cents: 6000,
        params: %{
          "entitlement_version" => 2,
          "package_type" => "membership",
          "fields" => %{
            "group_classes.included" => true,
            @visits => %{"limit" => 8, "period" => "calendar_month"}
          }
        }
      })

    assert %{fields: %{@visits => %{"limit" => 8}}, next_price_cents: 6000} =
             PackageStart.taken(PackageStart.changes(bought(), fewer))
  end
end

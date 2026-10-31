defmodule Palee.Finance.Domain.PurchaseRulesTest do
  use ExUnit.Case, async: true

  alias Palee.Finance.Domain.{PackageCatalog, SubscriptionSelection}

  @package "00000000-0000-0000-0000-00000000000a"
  @intro "00000000-0000-0000-0000-00000000000b"
  @today ~D[2027-05-05]

  defp params(fields),
    do: %{"entitlement_version" => 2, "package_type" => "membership", "fields" => fields}

  defp held(package_id, attrs \\ %{}) do
    Map.merge(
      %{
        membership_package_id: package_id,
        params_snapshot: params(%{}),
        status: "expired",
        starts_on: ~D[2027-01-01],
        ends_on: ~D[2027-01-31]
      },
      attrs
    )
  end

  test "the new fields are authorable and validated" do
    for key <- ~w(terms.buyers terms.max_purchases_per_person terms.prerequisite_package_ids
                  booking.daily_limit booking.weekly_limit booking.open_bookings_limit) do
      assert PackageCatalog.available?(key), key
    end

    {:ok, spec} = PackageCatalog.fetch("booking.daily_limit")
    assert PackageCatalog.cast(spec, nil) == {:ok, nil}
    assert PackageCatalog.cast(spec, 1) == {:ok, 1}
    assert PackageCatalog.cast(spec, 0) == {:error, :out_of_range}

    {:ok, spec} = PackageCatalog.fetch("terms.prerequisite_package_ids")
    assert PackageCatalog.cast(spec, []) == {:ok, []}
    assert PackageCatalog.cast(spec, [@intro, @intro]) == {:ok, [@intro]}
    assert PackageCatalog.cast(spec, ["nope"]) == {:error, :invalid_id}

    {:ok, spec} = PackageCatalog.fetch("terms.buyers")
    assert PackageCatalog.cast(spec, "everyone") == {:error, :invalid_option}
  end

  test "a staff-only package is refused to the member, not to staff" do
    p = params(%{"terms.buyers" => "staff_only"})

    assert SubscriptionSelection.eligible?(@package, p, [], channel: :member) ==
             {:error, :package_staff_only}

    assert SubscriptionSelection.eligible?(@package, p, [], channel: :staff) == :ok
  end

  test "a person buys it at most N times" do
    p = params(%{"terms.max_purchases_per_person" => 2})
    assert SubscriptionSelection.eligible?(@package, p, [held(@package)]) == :ok

    assert SubscriptionSelection.eligible?(@package, p, [held(@package), held(@package)]) ==
             {:error, :package_purchase_limit_reached}
  end

  test "a prerequisite package must have been held" do
    p = params(%{"terms.prerequisite_package_ids" => [@intro]})

    assert SubscriptionSelection.eligible?(@package, p, []) ==
             {:error, :package_prerequisite_missing}

    assert SubscriptionSelection.eligible?(@package, p, [held(@intro)]) == :ok
  end

  test "an add-on for active members needs an active package that day" do
    p = params(%{"terms.buyers" => "active_members"})

    assert SubscriptionSelection.eligible?(@package, p, [held(@intro)], today: @today) ==
             {:error, :package_active_members_only}

    active = held(@intro, %{status: "active", starts_on: ~D[2027-05-01], ends_on: nil})
    assert SubscriptionSelection.eligible?(@package, p, [active], today: @today) == :ok

    later = held(@intro, %{status: "active", starts_on: ~D[2027-06-01], ends_on: nil})

    assert SubscriptionSelection.eligible?(@package, p, [later], today: @today) ==
             {:error, :package_active_members_only}
  end

  test "the rules from before still hold" do
    once = params(%{"terms.once_per_person" => true})

    assert SubscriptionSelection.eligible?(@package, once, [held(@package)]) ==
             {:error, :package_already_used}
  end
end

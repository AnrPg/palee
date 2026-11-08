defmodule Palee.Finance.Domain.PackageAudienceTest do
  use ExUnit.Case, async: true

  alias Palee.Finance.Domain.PackageAudience

  @pkg "11111111-1111-1111-1111-111111111111"
  @other "22222222-2222-2222-2222-222222222222"
  @person "33333333-3333-3333-3333-333333333333"

  defp policy(box, packages \\ %{}, exceptions \\ []),
    do: PackageAudience.policy(box, packages, exceptions)

  defp holder(holds \\ [@pkg]), do: PackageAudience.viewer(@person, holds)
  defp stranger, do: PackageAudience.viewer(@person, [])

  defp exception(effect, package_id \\ nil),
    do: %{user_id: @person, effect: effect, package_id: package_id}

  describe "decide/3" do
    test "the box's audience when nothing more specific speaks" do
      assert {true, {:box, "all"}} = PackageAudience.decide(@pkg, policy("all"), stranger())
      assert {false, {:box, "none"}} = PackageAudience.decide(@pkg, policy("none"), holder())
      assert {true, {:box, "own"}} = PackageAudience.decide(@pkg, policy("own"), holder())
      assert {false, {:box, "own"}} = PackageAudience.decide(@pkg, policy("own"), stranger())
    end

    test "someone not signed in holds nothing" do
      anonymous = PackageAudience.anonymous()
      assert {false, _} = PackageAudience.decide(@pkg, policy("own"), anonymous)
      assert {true, _} = PackageAudience.decide(@pkg, policy("all"), anonymous)
    end

    test "the package's own audience wins over the box's" do
      assert {true, {:package, "all"}} =
               PackageAudience.decide(@pkg, policy("none", %{@pkg => "all"}), stranger())

      assert {false, {:package, "none"}} =
               PackageAudience.decide(@pkg, policy("all", %{@pkg => "none"}), holder())

      assert {false, {:package, "own"}} =
               PackageAudience.decide(@pkg, policy("all", %{@pkg => "own"}), stranger())

      assert {false, {:box, "none"}} =
               PackageAudience.decide(@pkg, policy("none", %{@pkg => nil}), stranger())
    end

    test "a box-wide person exception wins over every audience" do
      shown = policy("none", %{@pkg => "none"}, [exception("show")])
      assert {true, {:person, :box, :show}} = PackageAudience.decide(@pkg, shown, stranger())

      hidden = policy("all", %{@pkg => "all"}, [exception("hide")])
      assert {false, {:person, :box, :hide}} = PackageAudience.decide(@pkg, hidden, holder())
    end

    test "a package person exception wins over a box-wide one" do
      policy = policy("all", %{}, [exception("hide"), exception("show", @pkg)])
      assert {true, {:person, :package, :show}} = PackageAudience.decide(@pkg, policy, stranger())
      assert {false, {:person, :box, :hide}} = PackageAudience.decide(@other, policy, stranger())
    end

    test "hide wins over show at the same level" do
      policy = policy("all", %{}, [exception("show", @pkg), exception("hide", @pkg)])
      assert {false, {:person, :package, :hide}} = PackageAudience.decide(@pkg, policy, holder())
    end

    test "exceptions never apply to someone not signed in, nor to someone else" do
      policy = policy("all", %{}, [exception("hide")])
      assert {true, _} = PackageAudience.decide(@pkg, policy, PackageAudience.anonymous())

      someone = PackageAudience.viewer("44444444-4444-4444-4444-444444444444", [])
      assert {true, _} = PackageAudience.decide(@pkg, policy, someone)
    end

    test "unknown stored values read safely" do
      assert %PackageAudience{box: "all", packages: %{@pkg => nil}, exceptions: []} =
               PackageAudience.policy(nil, %{@pkg => "maybe"}, [%{user_id: @person, effect: "x"}])
    end
  end

  describe "view/3" do
    test "own_only when the viewer sees what they hold and others are kept for holders" do
      packages = [%{id: @pkg}, %{id: @other}]

      assert %{packages: [%{id: @pkg}], held: [@pkg], own_only: true} =
               PackageAudience.view(packages, policy("own"), holder())

      assert %{packages: [], own_only: false} =
               PackageAudience.view(packages, policy("own"), stranger())

      assert %{packages: [_, _], own_only: false} =
               PackageAudience.view(packages, policy("all"), holder())

      assert %{packages: [], own_only: false} =
               PackageAudience.view(packages, policy("none"), holder())
    end

    test "two held packages: both shown" do
      packages = [%{id: @pkg}, %{id: @other}]

      assert %{packages: [_, _], own_only: false} =
               PackageAudience.view(packages, policy("own"), holder([@pkg, @other]))
    end
  end

  describe "holdings/2" do
    test "running subscriptions, plus the latest while still a member" do
      old = %{membership_package_id: @other, status: "expired", starts_on: ~D[2026-01-01]}
      latest = %{membership_package_id: @pkg, status: "expired", starts_on: ~D[2026-10-01]}

      assert PackageAudience.holdings([old, latest], true) == [@pkg]
      assert PackageAudience.holdings([old, latest], false) == []

      running = %{old | status: "active"}

      assert Enum.sort(PackageAudience.holdings([running, latest], true)) ==
               Enum.sort([@other, @pkg])

      assert PackageAudience.holdings([running, latest], false) == [@other]
      assert PackageAudience.holdings([], true) == []
    end

    test "the latest is the one starting last, not the one listed last" do
      earlier = %{membership_package_id: @other, status: "cancelled", starts_on: ~D[2026-02-01]}
      later = %{membership_package_id: @pkg, status: "expired", starts_on: ~D[2026-09-30]}
      assert PackageAudience.holdings([later, earlier], true) == [@pkg]
    end
  end
end

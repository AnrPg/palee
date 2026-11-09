defmodule Palee.Organizations.Domain.MembershipPolicyTest do
  use ExUnit.Case, async: true

  alias Palee.Organizations.Domain.{JoinLinkPolicy, JoinRequestPolicy, MembershipPolicy}

  test "keeps tenant roles distinct from membership lifecycle" do
    assert MembershipPolicy.roles() == [
             :owner,
             :admin,
             :coach,
             :front_desk,
             :accountant,
             :janitor,
             :member,
             :athlete,
             :guest
           ]

    assert MembershipPolicy.statuses() == [:invited, :active, :suspended, :revoked]
  end

  test "only active memberships authorize tenant access" do
    assert MembershipPolicy.authorized_status?(:active)
    refute MembershipPolicy.authorized_status?(:invited)
    refute MembershipPolicy.authorized_status?(:suspended)
    refute MembershipPolicy.authorized_status?(:revoked)
  end

  # The "only owners and admins may manage invitations" rule used to be
  # asserted here against can_manage_invitations?/1, which nothing called. It
  # is now asserted against the live paths instead - see
  # organizations_test.exs ("a member cannot issue invitations") and
  # set_membership_role_test.exs ("a coach cannot change roles at all").

  describe "the guest role (ADR-272)" do
    test "is the lowest tier, below every client role" do
      assert MembershipPolicy.tier(:guest) > 0
      assert MembershipPolicy.tier(:member) > MembershipPolicy.tier(:guest)
      assert MembershipPolicy.tier(:athlete) > MembershipPolicy.tier(:guest)
    end

    test "buys like a client but is neither a client nor staff" do
      assert MembershipPolicy.guest?([:guest])
      assert MembershipPolicy.buyer?([:guest])
      refute MembershipPolicy.client?([:guest])
      refute MembershipPolicy.staff?([:guest])
      assert MembershipPolicy.buyer_role([:guest]) == :guest
      assert MembershipPolicy.buyer_role([:member, :guest]) == :member
      assert MembershipPolicy.buyer_role([:coach]) == nil
      refute MembershipPolicy.buyer?([:front_desk])
    end

    test "only a guest with no client or staff role is guest-only" do
      assert MembershipPolicy.guest_only?([:guest])
      assert MembershipPolicy.guest_only?(["guest"])
      refute MembershipPolicy.guest_only?([:member, :guest])
      refute MembershipPolicy.guest_only?([:front_desk, :guest])
      refute MembershipPolicy.guest_only?([:member])
    end

    test "staff who invite clients may make someone a guest; nobody makes themselves one" do
      for issuer <- [[:owner], [:admin], [:coach], [:front_desk]],
          do: assert(MembershipPolicy.can_grant_role?(issuer, :guest))

      refute MembershipPolicy.can_grant_role?([:accountant], :guest)
      refute MembershipPolicy.can_grant_role?([:member], :guest)
      assert MembershipPolicy.can_manage_member?([:front_desk], [:guest])
      refute MembershipPolicy.can_manage_member?([:guest], [:guest])
      refute MembershipPolicy.self_assignable_role?([:owner], :guest)
      refute MembershipPolicy.self_assignable_role?([:member], :guest)

      assert :ok =
               MembershipPolicy.authorize_role_change([:front_desk], [:guest], [:member], :other)
    end
  end

  describe "the role hierarchy (ADR-219)" do
    test "ranks owner over admin over staff over clients; a tier's roles are peers" do
      assert MembershipPolicy.tier(:owner) > MembershipPolicy.tier(:admin)
      assert MembershipPolicy.tier(:admin) > MembershipPolicy.tier(:coach)

      for staff <- [:front_desk, :accountant, :janitor],
          do: assert(MembershipPolicy.tier(staff) == MembershipPolicy.tier(:coach))

      assert MembershipPolicy.tier(:coach) > MembershipPolicy.tier(:member)
      assert MembershipPolicy.tier(:member) == MembershipPolicy.tier(:athlete)
      assert MembershipPolicy.top_tier([:member, :admin]) == MembershipPolicy.tier(:admin)
      assert MembershipPolicy.top_tier([]) == 0
    end

    test "people act only on those ranked below them; owners also on co-owners" do
      assert MembershipPolicy.can_manage_member?([:admin], [:coach, :member])
      refute MembershipPolicy.can_manage_member?([:admin], [:admin])
      refute MembershipPolicy.can_manage_member?([:admin, :coach], [:owner, :member])
      refute MembershipPolicy.can_manage_member?([:coach], [:front_desk])
      assert MembershipPolicy.can_manage_member?([:coach], [:athlete])
      assert MembershipPolicy.can_manage_member?([:owner], [:owner, :coach])
    end

    test "on someone else every changed role must be grantable and the target ranked below" do
      assert :ok =
               MembershipPolicy.authorize_role_change(
                 [:admin],
                 [:member],
                 [:coach, :member],
                 :other
               )

      # Lower roles of a fellow admin or of an owner are out of reach.
      assert {:error, :role_ceiling_exceeded} =
               MembershipPolicy.authorize_role_change(
                 [:admin],
                 [:admin],
                 [:admin, :coach],
                 :other
               )

      assert {:error, :role_ceiling_exceeded} =
               MembershipPolicy.authorize_role_change(
                 [:admin],
                 [:owner, :member],
                 [:owner],
                 :other
               )

      assert {:error, :role_ceiling_exceeded} =
               MembershipPolicy.authorize_role_change([:admin], [:coach], [:admin], :other)

      assert :ok =
               MembershipPolicy.authorize_role_change(
                 [:owner],
                 [:owner, :coach],
                 [:admin],
                 :other
               )
    end

    test "on oneself only roles below the top role move" do
      assert :ok =
               MembershipPolicy.authorize_role_change([:owner], [:owner], [:owner, :coach], :self)

      assert :ok =
               MembershipPolicy.authorize_role_change(
                 [:owner, :coach],
                 [:owner, :coach],
                 [:owner, :member],
                 :self
               )

      assert :ok =
               MembershipPolicy.authorize_role_change(
                 [:coach],
                 [:coach],
                 [:coach, :member],
                 :self
               )

      # The top role never changes, nor does a peer of it.
      assert {:error, :own_top_role_locked} =
               MembershipPolicy.authorize_role_change([:owner], [:owner], [:coach], :self)

      assert {:error, :own_top_role_locked} =
               MembershipPolicy.authorize_role_change([:admin], [:admin], [:admin, :owner], :self)

      assert {:error, :own_top_role_locked} =
               MembershipPolicy.authorize_role_change(
                 [:coach],
                 [:coach],
                 [:coach, :front_desk],
                 :self
               )

      assert {:error, :own_top_role_locked} =
               MembershipPolicy.authorize_role_change(
                 [:member],
                 [:member],
                 [:member, :athlete],
                 :self
               )
    end
  end

  describe "ADR-595: leaving the box" do
    @left_at ~U[2026-11-09 18:00:00Z]

    test "a former member is one who left; the box stays reachable while their package lasts" do
      left = %{left_at: @left_at, access_until: ~D[2026-11-28], roles: [:member]}

      assert MembershipPolicy.former?(left)
      refute MembershipPolicy.former?(%{left_at: nil, roles: [:member]})

      assert MembershipPolicy.reaches_box?(left, ~D[2026-11-28])
      refute MembershipPolicy.reaches_box?(left, ~D[2026-11-29])
      refute MembershipPolicy.reaches_box?(%{left | access_until: nil}, ~D[2026-11-09])
      assert MembershipPolicy.reaches_box?(%{left_at: nil}, ~D[2030-01-01])
    end

    test "only a client's membership ends by leaving; staff keep working there" do
      assert MembershipPolicy.can_leave?(%{left_at: nil, roles: [:member]})
      assert MembershipPolicy.can_leave?(%{left_at: nil, roles: [:athlete]})
      refute MembershipPolicy.can_leave?(%{left_at: nil, roles: [:coach, :member]})
      refute MembershipPolicy.can_leave?(%{left_at: nil, roles: [:guest]})
      refute MembershipPolicy.can_leave?(%{left_at: @left_at, roles: [:member]})
    end

    test "someone who left joins again by any way in" do
      left = %{status: :active, left_at: @left_at}

      assert JoinLinkPolicy.join_decision(left) == :create
      assert JoinRequestPolicy.admission(left, :purchase) == :create
      assert JoinRequestPolicy.admission(left, :accepted_request) == :create

      assert JoinRequestPolicy.admission(%{status: :active, left_at: nil}, :purchase) ==
               :already_member
    end
  end
end

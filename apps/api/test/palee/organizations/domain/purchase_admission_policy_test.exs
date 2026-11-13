defmodule Palee.Organizations.Domain.PurchaseAdmissionPolicyTest do
  use ExUnit.Case, async: true

  alias Palee.Organizations.Domain.PurchaseAdmissionPolicy, as: Policy

  @at ~U[2026-11-13 10:00:00Z]
  @later ~U[2026-11-13 11:00:00Z]

  defp row(roles, mark), do: %{roles: roles, purchase_admission_at: mark}

  test "starting to buy admits a marked guest" do
    assert Policy.admitted(@at) == %{role: :guest, roles: [:guest], purchase_admission_at: @at}
  end

  test "«Το θέλω» makes any guest a member, keeping or setting the mark" do
    assert Policy.on_request(row([:guest], @at), @later) ==
             {:promote, %{roles: [:member], purchase_admission_at: @at}}

    # A desk guest (ADR-272) asking becomes a member on the same terms.
    assert Policy.on_request(row([:guest], nil), @later) ==
             {:promote, %{roles: [:member], purchase_admission_at: @later}}

    assert Policy.on_request(row([:member], nil), @later) == :keep
    assert Policy.on_request(row([:coach], nil), @later) == :keep
  end

  test "a package completes a marked admission and leaves everyone else alone" do
    assert Policy.on_package(row([:guest], @at)) ==
             {:promote, %{roles: [:member], purchase_admission_at: nil}}

    assert Policy.on_package(row([:member], @at)) == {:settle, %{purchase_admission_at: nil}}
    # A desk guest sold a package by staff stays a guest (ADR-272).
    assert Policy.on_package(row([:guest], nil)) == :keep
    assert Policy.on_package(row([:member], nil)) == :keep
  end

  test "a request closed with no package makes a marked member a guest, unless something holds them" do
    assert Policy.on_request_closed(row([:member], @at), false) == {:demote, %{roles: [:guest]}}
    assert Policy.on_request_closed(row([:member], @at), true) == :keep
    assert Policy.on_request_closed(row([:member], nil), false) == :keep
    assert Policy.on_request_closed(row([:member, :coach], @at), false) == :keep
  end
end

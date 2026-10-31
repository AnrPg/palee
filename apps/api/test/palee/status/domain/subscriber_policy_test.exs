defmodule Palee.Status.Domain.SubscriberPolicyTest do
  use ExUnit.Case, async: true

  alias Palee.Status.Domain.SubscriberPolicy

  test "normalize_email/1" do
    assert {:ok, "jo@box.gr"} = SubscriberPolicy.normalize_email("  Jo@Box.GR ")
    assert {:error, :invalid_email} = SubscriberPolicy.normalize_email("not an email")
    assert {:error, :invalid_email} = SubscriberPolicy.normalize_email(nil)
  end

  test "locale/1 keeps supported languages" do
    assert SubscriberPolicy.locale("el") == "el"
    assert SubscriberPolicy.locale("el-GR") == "el"
    assert SubscriberPolicy.locale("pt-BR") == "pt_PT"
    assert SubscriberPolicy.locale("ja") == "en"
    assert SubscriberPolicy.locale(nil) == "en"
  end

  test "digest/1 is stable lower-case hex" do
    assert SubscriberPolicy.digest("a") == SubscriberPolicy.digest("a")
    assert SubscriberPolicy.digest("a") =~ ~r/^[0-9a-f]{64}$/
  end

  test "on_request/1 and expired?/2" do
    now = ~U[2026-11-02 10:00:00Z]
    assert SubscriberPolicy.on_request(nil) == :create
    assert SubscriberPolicy.on_request(%{confirmed_at: nil}) == :refresh
    assert SubscriberPolicy.on_request(%{confirmed_at: now}) == :already_confirmed

    refute SubscriberPolicy.expired?(%{confirmed_at: nil, updated_at: DateTime.add(now, -3600)}, now)
    assert SubscriberPolicy.expired?(%{confirmed_at: nil, updated_at: DateTime.add(now, -49 * 3600)}, now)
    refute SubscriberPolicy.expired?(%{confirmed_at: now, updated_at: DateTime.add(now, -99 * 3600)}, now)
  end
end

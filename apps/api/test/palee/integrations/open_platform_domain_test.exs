defmodule Palee.Integrations.OpenPlatformDomainTest do
  @moduledoc "ADR-378..380: the pure rules of keys, webhooks, idempotency and list sync."

  use ExUnit.Case, async: true

  alias Palee.Integrations.Domain.{
    ApiKeyToken,
    AudienceSyncPlan,
    DeliveryPolicy,
    EndpointUrl,
    Idempotency,
    PublicEvents,
    Scopes,
    WebhookSignature
  }

  describe "API key tokens" do
    test "a new token parses back to its prefix and matches only its own hash" do
      token = ApiKeyToken.new("live", :crypto.strong_rand_bytes(ApiKeyToken.random_bytes_needed()))

      assert token.token =~ ~r/\Apalee_live_[a-z2-7]{12}_[a-z2-7]{40}\z/
      assert {:ok, prefix} = ApiKeyToken.parse(token.token)
      assert prefix == token.prefix
      assert ApiKeyToken.matches?(token.token, token.hash)
      refute ApiKeyToken.matches?(token.token <> "x", token.hash)
      refute ApiKeyToken.matches?(token.token, nil)
      assert ApiKeyToken.masked("live", prefix) == "palee_live_#{prefix}_…"
    end

    test "malformed tokens are refused before any lookup" do
      for bad <- [
            "",
            "palee_live_short_secret",
            "palee_prod_aaaaaaaaaaaa_" <> String.duplicate("a", 40),
            "palee_live_AAAAAAAAAAAA_" <> String.duplicate("a", 40),
            "Bearer palee_live_aaaaaaaaaaaa_" <> String.duplicate("a", 40)
          ] do
        assert ApiKeyToken.parse(bad) == :error
      end
    end
  end

  describe "scopes" do
    test "normalize keeps known scopes sorted and unique; write never implies read" do
      assert {:ok, ["bookings:write", "members:read"]} =
               Scopes.normalize(["members:read", "bookings:write", "members:read"])

      assert {:error, :invalid_scopes} = Scopes.normalize(["payments:write"])
      assert {:error, :invalid_scopes} = Scopes.normalize([])
      refute Scopes.allows?(["members:write"], "members:read")
      refute "payments:write" in Scopes.all()
      assert Enum.all?(Scopes.catalog(), &(&1.en != "" and &1.el != ""))
    end
  end

  describe "webhook signatures" do
    test "a receiver verifies with the secret and refuses stale, tampered or foreign ones" do
      body = ~s({"id":"1","type":"ping"})
      header = WebhookSignature.header(["whsec_a"], 1_700_000_000, body)

      assert header =~ ~r/\At=1700000000,v1=[0-9a-f]{64}\z/
      assert :ok = WebhookSignature.verify("whsec_a", header, body, 1_700_000_100)
      assert {:error, :stale} = WebhookSignature.verify("whsec_a", header, body, 1_700_001_000)
      assert {:error, :mismatch} = WebhookSignature.verify("whsec_a", header, body <> " ", 1_700_000_000)
      assert {:error, :mismatch} = WebhookSignature.verify("whsec_b", header, body, 1_700_000_000)
      assert {:error, :malformed} = WebhookSignature.verify("whsec_a", "v1=abc", body, 1_700_000_000)
    end

    test "during a secret rotation both secrets verify" do
      header = WebhookSignature.header(["new", "old"], 10, "{}")

      assert :ok = WebhookSignature.verify("new", header, "{}", 10)
      assert :ok = WebhookSignature.verify("old", header, "{}", 10)
    end
  end

  describe "delivery policy" do
    @now ~U[2026-11-01 10:00:00Z]

    test "2xx succeeds, 410 fails at once, anything else retries on the schedule" do
      assert DeliveryPolicy.classify({:ok, 204}) == :succeeded
      assert DeliveryPolicy.classify({:ok, 410}) == :gone
      assert DeliveryPolicy.classify({:ok, 500}) == :failed
      assert DeliveryPolicy.classify({:error, :timeout}) == :failed
      assert DeliveryPolicy.classify({:error, :blocked_address}) == :blocked

      assert {:pending, at} = DeliveryPolicy.after_attempt(:failed, 1, @now)
      assert DateTime.diff(at, @now) == 60
      assert {:pending, at} = DeliveryPolicy.after_attempt(:failed, 8, @now)
      assert DateTime.diff(at, @now) == 86_400
      assert {:failed, nil} = DeliveryPolicy.after_attempt(:failed, DeliveryPolicy.max_attempts(), @now)
      assert {:failed, nil} = DeliveryPolicy.after_attempt(:gone, 1, @now)
      assert DeliveryPolicy.max_attempts() == 9
    end

    test "an endpoint is turned off when gone, blocked, or after 20 failures in a row" do
      assert DeliveryPolicy.endpoint_after(:succeeded, 19) == :healthy
      assert DeliveryPolicy.endpoint_after(:failed, 3) == :count
      assert {:disable, _reason} = DeliveryPolicy.endpoint_after(:failed, 19)
      assert {:disable, "gone"} = DeliveryPolicy.endpoint_after(:gone, 0)
      assert {:disable, "blocked_address"} = DeliveryPolicy.endpoint_after(:blocked, 0)
    end
  end

  describe "public events" do
    test "domain events become thin events with ids only" do
      assert {:ok, "booking.created", data} =
               PublicEvents.from_domain(:booking_made, %{
                 booking_id: "b",
                 scheduled_class_id: "c",
                 user_id: "u",
                 display_name: "Μαρία",
                 email: "maria@example.com"
               })

      assert data == %{booking_id: "b", class_id: "c", member_id: "u"}

      assert {:ok, "booking.cancelled", %{cancelled_by: "staff"}} =
               PublicEvents.from_domain(:booking_cancelled, %{booking_id: "b", by: :staff})

      assert :ignore = PublicEvents.from_domain(:workout_logged, %{user_id: "u"})
      assert PublicEvents.scope_for("payment.recorded") == "payments:read"
      assert {:error, :invalid_events} = PublicEvents.normalize(["booking.created", "nope"])
    end

    test "the envelope is versioned" do
      envelope = PublicEvents.envelope("e", "ping", %{}, "o", ~U[2026-11-01 10:00:00Z])

      assert envelope.api_version == PublicEvents.api_version()
      assert envelope.created_at == "2026-11-01T10:00:00Z"
    end
  end

  describe "endpoint URLs" do
    test "only https to a public host" do
      assert {:ok, "https://hooks.zapier.com/x"} = EndpointUrl.validate(" https://hooks.zapier.com/x ")

      for bad <- [
            "http://example.com",
            "https://localhost/x",
            "https://127.0.0.1/x",
            "https://10.1.2.3/x",
            "https://169.254.169.254/latest",
            "https://[::1]/x",
            "https://user:pass@example.com",
            "ftp://example.com",
            "https://" <> String.duplicate("a", 2001)
          ] do
        assert {:error, :invalid_webhook_url} = EndpointUrl.validate(bad), bad
      end

      assert {:ok, _url} = EndpointUrl.validate("http://localhost:4000/x", allow_http: true, allow_private: true)
    end

    test "private addresses are recognised" do
      assert EndpointUrl.private_address?({192, 168, 1, 1})
      assert EndpointUrl.private_address?({100, 64, 0, 1})
      assert EndpointUrl.private_address?({0xFD00, 0, 0, 0, 0, 0, 0, 1})
      refute EndpointUrl.private_address?({8, 8, 8, 8})
    end
  end

  describe "idempotency" do
    test "the fingerprint ignores key order and the decision follows the stored record" do
      a = Idempotency.fingerprint("bookings.create", %{"a" => 1, "b" => %{"x" => [1, 2]}})
      b = Idempotency.fingerprint("bookings.create", %{"b" => %{"x" => [1, 2]}, "a" => 1})

      assert a == b
      refute a == Idempotency.fingerprint("bookings.cancel", %{"a" => 1, "b" => %{"x" => [1, 2]}})

      done = %{request_hash: a, state: "completed", response_status: 201, response_body: %{"id" => 1}}
      assert {:replay, 201, %{"id" => 1}} = Idempotency.decide(done, a)
      assert {:error, :idempotency_key_in_use} = Idempotency.decide(%{done | state: "running"}, a)
      assert {:error, :idempotency_key_reused} = Idempotency.decide(done, "other")
    end

    test "keys are 1 to 255 visible ASCII characters" do
      assert {:ok, "abc-123"} = Idempotency.validate_key("abc-123")
      assert {:error, :invalid_idempotency_key} = Idempotency.validate_key("")
      assert {:error, :invalid_idempotency_key} = Idempotency.validate_key("has space")
      assert {:error, :invalid_idempotency_key} = Idempotency.validate_key(String.duplicate("a", 256))
    end
  end

  describe "email list sync plan" do
    test "subscribes only who wants it now and unsubscribes who no longer does" do
      maria = %{user_id: "m", email: "Maria@Example.com", first_name: "Μαρία"}
      nikos = %{user_id: "n", email: "nikos@example.com", first_name: "Νίκος"}

      synced = [
        %{user_id: "m", email_hash: AudienceSyncPlan.email_hash("maria@example.com"), status: "subscribed"},
        %{user_id: "x", email_hash: "h", status: "subscribed"},
        %{user_id: "y", email_hash: "h", status: "unsubscribed"}
      ]

      plan = AudienceSyncPlan.plan([maria, nikos], synced)

      assert plan.subscribe == [nikos]
      assert Enum.map(plan.unsubscribe, & &1.user_id) == ["x"]

      changed = %{maria | email: "maria.new@example.com"}
      assert [^changed, ^nikos] = AudienceSyncPlan.plan([changed, nikos], synced).subscribe
    end

    test "Mailchimp's subscriber hash and the first name" do
      assert AudienceSyncPlan.mailchimp_subscriber_hash(" Urist.McVankab@freddiesjokes.com ") ==
               "62eeb292278cc15f5817cb78f7790b08"

      assert AudienceSyncPlan.first_name("  Μαρία Παπαδοπούλου ") == "Μαρία"
      assert AudienceSyncPlan.first_name(nil) == nil
    end
  end
end

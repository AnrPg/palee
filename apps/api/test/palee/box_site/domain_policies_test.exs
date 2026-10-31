defmodule Palee.BoxSite.DomainPoliciesTest do
  @moduledoc "ADR-352..354: the website's pure rules."

  use ExUnit.Case, async: true

  alias Palee.BoxSite.Domain.{
    ConsentPolicy,
    ConversionEvent,
    DomainPolicy,
    FormPolicy,
    Hostname,
    SiteSections,
    SiteSettingsPolicy
  }

  @now ~U[2026-11-02 10:00:00.000000Z]

  describe "SiteSections" do
    test "the owner's order keeps hero first and appends new keys" do
      assert ["hero", "faq", "about" | rest] =
               SiteSections.normalize_order(["faq", "hero", "about", "nope"])

      assert Enum.sort(["hero", "faq", "about" | rest]) == Enum.sort(SiteSections.keys())
    end

    test "hero cannot be hidden and unknown keys are refused" do
      assert {:error, :hidden_sections} = SiteSections.validate(SiteSections.keys(), ["hero"])
      assert {:error, :section_order} = SiteSections.validate(["blog"], [])
    end

    test "switches hide sections without data" do
      visible = SiteSections.visible(SiteSections.keys(), ["coaches"], %{forms_enabled: true})

      refute "coaches" in visible
      refute "schedule" in visible
      refute "faq" in visible
      refute "reviews" in visible
      assert "trial_form" in visible

      assert "schedule" in SiteSections.visible([], [], %{public_schedule: true})
    end
  end

  describe "SiteSettingsPolicy" do
    setup do: %{current: SiteSettingsPolicy.defaults()}

    test "a new tag bumps the banner version", %{current: current} do
      assert {:ok, %{meta_pixel_id: "123456789", banner_version: 2}} =
               SiteSettingsPolicy.changes(current, %{"meta_pixel_id" => " 123456789 "})

      assert {:ok, %{ga4_measurement_id: "G-ABC1234"}} =
               SiteSettingsPolicy.changes(current, %{"ga4_measurement_id" => "g-abc1234"})
    end

    test "removing a tag does not ask visitors again", %{current: current} do
      current = %{current | meta_pixel_id: "123456789"}
      assert {:ok, changes} = SiteSettingsPolicy.changes(current, %{"meta_pixel_id" => ""})
      assert changes == %{meta_pixel_id: nil}
    end

    test "bad tag ids, FAQ and sections are field errors", %{current: current} do
      assert {:error, {:invalid_fields, errors}} =
               SiteSettingsPolicy.changes(current, %{
                 "gtm_container_id" => "GTM",
                 "faq" => [%{"question" => "", "answer" => "x"}],
                 "hidden_sections" => ["hero"]
               })

      assert errors == %{gtm_container_id: "invalid", faq: "invalid", hidden_sections: "invalid"}

      too_many = for i <- 1..13, do: %{"question" => "Q#{i}", "answer" => "A"}

      assert {:error, {:invalid_fields, %{faq: "too_many"}}} =
               SiteSettingsPolicy.changes(current, %{"faq" => too_many})
    end

    test "the Conversions API needs a pixel and a token", %{current: current} do
      assert {:error, {:invalid_fields, %{meta_pixel_id: "required"}}} =
               SiteSettingsPolicy.changes(current, %{"conversions_api_enabled" => true})

      current = %{current | meta_pixel_id: "123456789"}

      assert {:error, {:invalid_fields, %{conversions_api_token: "required"}}} =
               SiteSettingsPolicy.changes(current, %{"conversions_api_enabled" => true})

      token = String.duplicate("a", 40)

      assert {:ok, %{conversions_api_enabled: true, conversions_api_token: ^token}} =
               SiteSettingsPolicy.changes(current, %{
                 "conversions_api_enabled" => true,
                 "conversions_api_token" => token
               })
    end

    test "public tags never carry the token" do
      settings = Map.put(SiteSettingsPolicy.defaults(), :conversions_api_token, "secret")
      refute Map.has_key?(SiteSettingsPolicy.public_tags(settings), :conversions_api_token)
      refute SiteSettingsPolicy.tracking?(settings)
    end
  end

  describe "Hostname" do
    @refused ["palee.app", "localhost"]

    test "normalises a host the owner pasted" do
      assert {:ok, "www.mybox.gr"} = Hostname.normalize(" https://WWW.MyBox.gr/ ", @refused)
      assert {:ok, "mybox.gr"} = Hostname.normalize("mybox.gr.", @refused)
    end

    test "refuses Palee's own hosts, IPs and single labels" do
      assert {:error, :platform_hostname} = Hostname.normalize("box.palee.app", @refused)
      assert {:error, :platform_hostname} = Hostname.normalize("palee.app", @refused)
      assert {:error, :invalid_hostname} = Hostname.normalize("10.0.0.1", @refused)
      assert {:error, :invalid_hostname} = Hostname.normalize("intranet", @refused)
      assert {:error, :invalid_hostname} = Hostname.normalize("-bad-.gr", @refused)
      assert {:error, :invalid_hostname} = Hostname.normalize(nil, @refused)
    end

    test "apex hosts" do
      assert Hostname.apex?("mybox.gr")
      assert Hostname.apex?("mybox.com.gr")
      refute Hostname.apex?("www.mybox.gr")
    end
  end

  describe "DomainPolicy" do
    defp domain(attrs),
      do:
        Map.merge(
          %{
            host: "www.mybox.gr",
            verification_token: "tok",
            status: "pending_dns",
            attempts: 0,
            inserted_at: @now
          },
          attrs
        )

    test "shows a TXT proof and a CNAME, or A records for an apex" do
      records = DomainPolicy.dns_records(domain(%{}), false, "sites.palee.app", ["1.2.3.4"])

      assert [
               %{
                 type: "TXT",
                 name: "_palee-challenge.www.mybox.gr",
                 value: "palee-site-verification=tok"
               },
               %{type: "CNAME", value: "sites.palee.app"}
             ] = records

      assert [_txt, %{type: "A", value: "1.2.3.4"}] =
               DomainPolicy.dns_records(domain(%{host: "mybox.gr"}), true, "sites.palee.app", [
                 "1.2.3.4"
               ])
    end

    test "DNS facts: TXT proof and routing by CNAME or our A records" do
      assert %{txt_ok: true, routing_ok: true} =
               DomainPolicy.dns_facts(
                 "tok",
                 ["palee-site-verification=tok"],
                 ["Sites.Palee.App."],
                 [],
                 "sites.palee.app",
                 []
               )

      assert %{txt_ok: false, routing_ok: true} =
               DomainPolicy.dns_facts("tok", [], [], ["1.2.3.4"], "sites.palee.app", ["1.2.3.4"])

      assert %{routing_ok: false} =
               DomainPolicy.dns_facts("tok", [], [], ["1.2.3.4", "9.9.9.9"], "x", ["1.2.3.4"])
    end

    test "pending_dns moves on when DNS is right, or retries with backoff" do
      ok = %{txt_ok: true, routing_ok: true, tls_ok: false}

      assert %{status: "pending_tls", verified_at: @now, last_error: "tls_not_ready"} =
               DomainPolicy.after_check(domain(%{}), ok, @now)

      assert %{status: "active", active_at: @now} =
               DomainPolicy.after_check(domain(%{}), %{ok | tls_ok: true}, @now)

      changes = DomainPolicy.after_check(domain(%{}), %{ok | txt_ok: false}, @now)
      assert changes.last_error == "dns_txt_missing"
      assert changes.attempts == 1
      assert DateTime.diff(changes.next_check_at, @now) == 300
    end

    test "pending_dns expires after 14 days" do
      old = domain(%{inserted_at: DateTime.add(@now, -15 * 86_400, :second)})

      assert %{status: "expired", next_check_at: nil} =
               DomainPolicy.after_check(
                 old,
                 %{txt_ok: false, routing_ok: false, tls_ok: false},
                 @now
               )
    end

    test "an active host breaks when DNS or TLS stop, and recovers" do
      active = domain(%{status: "active", active_at: @now})

      assert %{status: "broken", last_error: "dns_not_pointing"} =
               DomainPolicy.after_check(
                 active,
                 %{txt_ok: false, routing_ok: false, tls_ok: false},
                 @now
               )

      assert %{status: "broken", last_error: "tls_failed"} =
               DomainPolicy.after_check(
                 active,
                 %{txt_ok: false, routing_ok: true, tls_ok: false},
                 @now
               )

      broken = domain(%{status: "broken", active_at: @now, attempts: 3})

      assert %{status: "active", attempts: 0} =
               DomainPolicy.after_check(
                 broken,
                 %{txt_ok: false, routing_ok: true, tls_ok: true},
                 @now
               )
    end

    test "a pending_tls host whose DNS is gone goes back to pending_dns" do
      assert %{status: "pending_dns", last_error: "dns_not_pointing"} =
               DomainPolicy.after_check(
                 domain(%{status: "pending_tls"}),
                 %{txt_ok: true, routing_ok: false, tls_ok: false},
                 @now
               )
    end

    test "backoff tops out at a day; TLS only for verified hosts" do
      assert DomainPolicy.backoff(1) == 300
      assert DomainPolicy.backoff(99) == 86_400
      assert DomainPolicy.tls_allowed?("active")
      assert DomainPolicy.tls_allowed?("pending_tls")
      refute DomainPolicy.tls_allowed?("pending_dns")
      refute DomainPolicy.tls_allowed?("broken")
      assert DomainPolicy.new_token(:crypto.strong_rand_bytes(24)) |> byte_size() == 32
    end
  end

  describe "FormPolicy" do
    @valid %{"name" => " Μαρία ", "email" => "Maria@Example.gr", "privacy_ack" => true}

    test "a trial request needs a name, a contact and the privacy notice" do
      assert {:ok, attrs} = FormPolicy.validate("trial", @valid, @now)
      assert attrs.name == "Μαρία"
      assert attrs.email == "maria@example.gr"
      assert attrs.status == "pending"
      refute attrs.marketing_opt_in

      assert {:error, {:invalid_fields, errors}} = FormPolicy.validate("trial", %{}, @now)
      assert errors == %{name: "required", email: "email_or_phone", privacy_ack: "required"}
    end

    test "a contact form needs a message; phones are cleaned" do
      assert {:error, {:invalid_fields, %{message: "required"}}} =
               FormPolicy.validate("contact", @valid, @now)

      params = %{
        "name" => "Νίκος",
        "phone" => "+30 69 1234 5678",
        "message" => "Γεια",
        "privacy_ack" => true
      }

      assert {:ok, %{phone: "+306912345678", email: nil}} =
               FormPolicy.validate("contact", params, @now)
    end

    test "unknown forms, bad ids and attribution" do
      assert {:error, :unknown_form} = FormPolicy.validate("newsletter", @valid, @now)

      assert {:error, {:invalid_fields, %{visitor_id: "invalid"}}} =
               FormPolicy.validate("trial", Map.put(@valid, "visitor_id", "x"), @now)

      params = Map.put(@valid, "attribution", %{"evil" => "x", "utm_source" => "instagram"})

      assert {:ok, %{attribution: %{"utm_source" => "instagram"}}} =
               FormPolicy.validate("trial", params, @now)
    end

    test "bots: honeypot and too fast" do
      assert FormPolicy.spam?(%{"website" => "http://spam"})
      assert FormPolicy.spam?(%{"elapsed_ms" => 300})
      refute FormPolicy.spam?(%{"elapsed_ms" => 9_000, "website" => ""})
    end

    test "the intake contract and what delivery does" do
      {:ok, attrs} =
        FormPolicy.validate("trial", Map.put(@valid, "consent_text_version", "v1"), @now)

      submission = attrs |> Map.put(:id, Ecto.UUID.generate()) |> Map.put(:attempts, 1)
      intake = FormPolicy.intake(submission)

      assert intake.source == "website_form"
      assert intake.submission_id == submission.id
      assert intake.consent == %{text_version: "v1", text_hash: nil}
      assert intake.attribution.utm_source == nil

      lead = Ecto.UUID.generate()
      delivered = FormPolicy.after_delivery({:ok, %{lead_id: lead}}, submission, @now)

      assert %{status: "delivered", lead_id: ^lead, name: nil, email: nil, redacted_at: @now} =
               delivered

      assert %{status: "failed"} =
               FormPolicy.after_delivery({:error, {:rejected, :invalid_lead}}, submission, @now)

      retry = FormPolicy.after_delivery({:error, {:transient, :down}}, submission, @now)
      assert retry.status == "pending"
      assert DateTime.diff(retry.next_attempt_at, @now) == 60

      assert %{status: "failed"} =
               FormPolicy.after_delivery(
                 {:error, {:transient, :down}},
                 %{submission | attempts: 12},
                 @now
               )

      assert FormPolicy.backoff(20) == 21_600
    end
  end

  describe "ConsentPolicy" do
    @visitor "6f1c5a9e-6c0e-4c8e-9d3a-4b8f0b9c1a2d"

    test "accept and reject set both categories; custom takes the choice" do
      assert {:ok, %{analytics: true, marketing: true}} =
               ConsentPolicy.record(
                 %{"action" => "accept_all", "visitor_id" => @visitor, "banner_version" => 2},
                 2,
                 @now
               )

      assert {:ok, %{analytics: false, marketing: false} = row} =
               ConsentPolicy.record(
                 %{
                   "action" => "reject_all",
                   "visitor_id" => @visitor,
                   "banner_version" => 2,
                   "analytics" => true
                 },
                 2,
                 @now
               )

      assert DateTime.diff(row.expires_at, @now) == 182 * 86_400

      assert {:ok, %{analytics: true, marketing: false}} =
               ConsentPolicy.record(
                 %{
                   "action" => "custom",
                   "visitor_id" => @visitor,
                   "banner_version" => 2,
                   "analytics" => true
                 },
                 2,
                 @now
               )
    end

    test "a stale banner or bad input is refused" do
      assert {:error, {:invalid_fields, %{banner_version: "outdated"}}} =
               ConsentPolicy.record(
                 %{"action" => "accept_all", "visitor_id" => @visitor, "banner_version" => 1},
                 2,
                 @now
               )

      assert {:error, {:invalid_fields, %{action: "invalid", visitor_id: "invalid"}}} =
               ConsentPolicy.record(%{"action" => "maybe", "banner_version" => 2}, 2, @now)
    end

    test "a choice lapses with time and with a new banner" do
      consent = %{
        analytics: true,
        marketing: true,
        banner_version: 2,
        expires_at: DateTime.add(@now, 10)
      }

      assert %{marketing: true} = ConsentPolicy.effective(consent, 2, @now)
      assert %{marketing: false} = ConsentPolicy.effective(consent, 3, @now)
      assert %{marketing: false} = ConsentPolicy.effective(consent, 2, DateTime.add(@now, 11))
      assert %{analytics: false} = ConsentPolicy.effective(nil, 2, @now)
    end

    test "tags follow the categories; GTM with either" do
      tags = %{
        meta_pixel_id: "1234567",
        ga4_measurement_id: "G-AAAA",
        gtm_container_id: "GTM-AAAA"
      }

      assert ConsentPolicy.allowed_tags(tags, %{analytics: true, marketing: false}) ==
               [:ga4_measurement_id, :gtm_container_id]

      assert ConsentPolicy.allowed_tags(tags, %{analytics: false, marketing: true}) ==
               [:meta_pixel_id, :gtm_container_id]

      assert ConsentPolicy.allowed_tags(tags, %{analytics: false, marketing: false}) == []

      assert ConsentPolicy.allowed_tags(%{tags | gtm_container_id: nil}, %{
               analytics: true,
               marketing: true
             }) ==
               [:ga4_measurement_id, :meta_pixel_id]
    end
  end

  describe "ConversionEvent" do
    test "hashes normalised email and phone; the event id is the submission id" do
      id = Ecto.UUID.generate()

      event =
        ConversionEvent.build(
          %{id: id, email: " Maria@Example.GR ", phone: "6912345678", submitted_at: @now},
          "https://www.mybox.gr"
        )

      assert event["event_id"] == id
      assert event["event_name"] == "Lead"

      assert event["user_data"]["em"] == [
               Base.encode16(:crypto.hash(:sha256, "maria@example.gr"), case: :lower)
             ]

      assert event["user_data"]["ph"] == [
               Base.encode16(:crypto.hash(:sha256, "306912345678"), case: :lower)
             ]

      refute inspect(event) =~ "maria"

      assert ConversionEvent.build(%{id: id, email: nil, phone: nil, submitted_at: @now}, "u") ==
               nil
    end

    test "phones keep their country code" do
      assert ConversionEvent.normalize_phone("+44 20 7946 0958") == "442079460958"
      assert ConversionEvent.normalize_phone("0049301234567") == "49301234567"
      assert ConversionEvent.normalize_phone("2101234567") == "302101234567"
    end

    test "send outcomes clear the payload when done" do
      assert %{conversion_status: "sent", conversion_payload: nil} =
               ConversionEvent.after_send(:ok, 1, @now)

      assert %{conversion_status: "pending"} =
               ConversionEvent.after_send({:error, {:transient, :x}}, 1, @now)

      assert %{conversion_status: "failed"} =
               ConversionEvent.after_send({:error, {:transient, :x}}, 6, @now)

      assert %{conversion_status: "failed"} =
               ConversionEvent.after_send({:error, {:rejected, :x}}, 1, @now)
    end
  end
end

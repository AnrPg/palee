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

    test "ADR-530: photos, stats and programmes show only with data" do
      keys = SiteSections.keys()
      assert Enum.all?(~w(photos stats programmes), &(&1 in keys))
      assert hd(SiteSections.normalize_order(["stats", "photos"])) == "hero"

      none = SiteSections.visible([], [], %{})
      refute "photos" in none or "stats" in none or "programmes" in none

      all = SiteSections.visible([], [], %{photos?: true, stats?: true, programmes?: true})
      assert "photos" in all and "stats" in all and "programmes" in all
      assert hd(all) == "hero"

      refute "stats" in SiteSections.visible([], ["stats"], %{stats?: true})
    end
  end

  describe "SiteSettingsPolicy: ADR-530 look and draft" do
    setup do: %{current: SiteSettingsPolicy.defaults()}

    test "a new box: tiles, Palee palette, timetable on, WOD off", %{current: current} do
      assert %{
               template: "tiles",
               palette: "palee",
               appearance: "auto",
               calm_motion: false,
               public_schedule: true,
               public_wod: false,
               draft: nil,
               template_notice: false
             } = current
    end

    test "unknown keys are field errors", %{current: current} do
      assert {:error, {:invalid_fields, errors}} =
               SiteSettingsPolicy.changes(current, %{
                 "template" => "brutal",
                 "palette" => "#ff0000",
                 "appearance" => "sepia",
                 "calm_motion" => "yes"
               })

      assert errors == %{
               template: "invalid",
               palette: "invalid",
               appearance: "invalid",
               calm_motion: "invalid"
             }
    end

    test "publishable fields land in the draft; others save at once", %{current: current} do
      assert {:ok, changes} =
               SiteSettingsPolicy.changes(current, %{
                 "template" => "stories",
                 "palette" => "aegean",
                 "public_wod" => true,
                 "forms_enabled" => false
               })

      assert changes.forms_enabled == false
      refute Map.has_key?(changes, :template)
      refute Map.has_key?(changes, :public_wod)

      assert changes.draft == %{
               "template" => "stories",
               "palette" => "aegean",
               "public_wod" => true
             }
    end

    test "the draft merges and keeps only what differs from the live site",
         %{current: current} do
      current = %{current | draft: %{"template" => "stories", "calm_motion" => true}}

      assert {:ok, %{draft: %{"template" => "atelier", "calm_motion" => true}}} =
               SiteSettingsPolicy.changes(current, %{"template" => "atelier"})

      assert {:ok, %{draft: %{"calm_motion" => true}}} =
               SiteSettingsPolicy.changes(current, %{"template" => "tiles"})

      # Back to the live values: nothing waits any more.
      assert {:ok, %{draft: nil}} =
               SiteSettingsPolicy.changes(current, %{
                 "template" => "tiles",
                 "calm_motion" => false
               })

      # Hidden sections compare as a set.
      current = %{SiteSettingsPolicy.defaults() | hidden_sections: ["faq", "coaches"]}

      assert {:ok, %{draft: nil, section_order: _order}} =
               SiteSettingsPolicy.changes(current, %{"hidden_sections" => ["coaches", "faq"]})
    end

    test "publish applies the draft, clears it and hides the notice", %{current: current} do
      now = ~U[2026-11-04 10:00:00.000000Z]

      current = %{
        current
        | draft: %{"template" => "atelier", "hidden_sections" => ["stats"], "bogus" => 1},
          template_notice: true
      }

      assert SiteSettingsPolicy.drafted(current).template == "atelier"
      assert SiteSettingsPolicy.drafted(current).hidden_sections == ["stats"]

      assert SiteSettingsPolicy.publish(current, now) == %{
               template: "atelier",
               hidden_sections: ["stats"],
               draft: nil,
               published_at: now,
               template_notice: false
             }

      assert %{draft: nil, published_at: ^now} = SiteSettingsPolicy.publish(%{draft: nil}, now)
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

    test "refuses the system domains whatever the config says (ADR-398)" do
      for host <- ~w(palee.app www.palee.app 4kq.net milos.4kq.net x.milos.4kq.net
                     atha.gr www.atha.gr atha.io api.atha.io) do
        assert {:error, :platform_hostname} = Hostname.normalize(host, [])
      end

      assert {:ok, "notpalee.app"} = Hostname.normalize("NotPalee.app", [])
      assert {:ok, "atha.gr.example.com"} = Hostname.normalize("atha.gr.example.com", [])
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

    test "shows a TXT proof and a CNAME, or an ALIAS (flattening) for an apex" do
      records = DomainPolicy.dns_records(domain(%{}), false, "sites.palee.app")

      assert [
               %{
                 type: "TXT",
                 name: "_palee-challenge.www.mybox.gr",
                 value: "palee-site-verification=tok"
               },
               %{type: "CNAME", value: "sites.palee.app"}
             ] = records

      assert [_txt, %{type: "ALIAS", name: "mybox.gr", value: "sites.palee.app"}] =
               DomainPolicy.dns_records(domain(%{host: "mybox.gr"}), true, "sites.palee.app")
    end

    defp lookups(attrs) do
      Map.merge(
        %{
          txt: {:ok, []},
          cname_chain: {:ok, []},
          a: {:ok, []},
          aaaa: {:ok, []},
          target_a: {:ok, ["198.51.100.1", "198.51.100.2"]},
          target_aaaa: {:ok, []}
        },
        attrs
      )
    end

    defp facts(attrs), do: DomainPolicy.dns_facts("tok", lookups(attrs), "sites.palee.app")

    test "DNS facts: TXT proof, and routing by a CNAME chain to the target" do
      assert %{txt_ok: true, routing_ok: true} =
               facts(%{
                 txt: {:ok, [" palee-site-verification=tok "]},
                 cname_chain: {:ok, ["Sites.Palee.App."]}
               })

      assert %{routing_ok: true} =
               facts(%{cname_chain: {:ok, ["edge.mybox.gr", "sites.palee.app"]}})

      assert %{txt_ok: false, routing_ok: false} =
               facts(%{cname_chain: {:ok, ["elsewhere.example.com"]}, a: {:ok, ["203.0.113.9"]}})
    end

    test "DNS facts: a flattened apex passes when every address is the target's now" do
      assert %{routing_ok: true} = facts(%{a: {:ok, ["198.51.100.2"]}})
      assert %{routing_ok: true} = facts(%{a: {:ok, ["198.51.100.1", "198.51.100.2"]}})
      # One stale or foreign address fails: some visitors would land elsewhere.
      assert %{routing_ok: false} = facts(%{a: {:ok, ["198.51.100.1", "203.0.113.9"]}})
      # No address at all.
      assert %{routing_ok: false} = facts(%{})

      # AAAA, when present, must be the target's too.
      assert %{routing_ok: false} =
               facts(%{a: {:ok, ["198.51.100.1"]}, aaaa: {:ok, ["2001:db8::1"]}})

      assert %{routing_ok: true} =
               facts(%{
                 a: {:ok, ["198.51.100.1"]},
                 aaaa: {:ok, ["2001:DB8::1"]},
                 target_aaaa: {:ok, ["2001:db8::1"]}
               })
    end

    test "DNS facts: what the resolver could not tell is unknown, not a failure" do
      assert %{txt_ok: :unknown} = facts(%{txt: {:error, :timeout}})

      assert %{routing_ok: :unknown} =
               facts(%{cname_chain: {:error, :timeout}, a: {:ok, ["203.0.113.9"]}})

      assert %{routing_ok: :unknown} = facts(%{a: {:error, :servfail}})
      assert %{routing_ok: :unknown} = facts(%{target_a: {:error, :timeout}})
      # Palee's own name resolving to nothing is Palee's problem.
      assert %{routing_ok: :unknown} = facts(%{a: {:ok, ["203.0.113.9"]}, target_a: {:ok, []}})

      # A proof on either side still decides.
      assert %{routing_ok: true} =
               facts(%{cname_chain: {:error, :timeout}, a: {:ok, ["198.51.100.1"]}})

      assert %{routing_ok: true} =
               facts(%{cname_chain: {:ok, ["sites.palee.app"]}, target_a: {:error, :timeout}})
    end

    test "unknown DNS keeps every state and looks again in 5 minutes" do
      for status <- ~w(pending_dns pending_tls active broken) do
        unknown = %{txt_ok: true, routing_ok: :unknown, tls_ok: false}
        changes = DomainPolicy.after_check(domain(%{status: status, attempts: 2}), unknown, @now)
        assert Map.keys(changes) |> Enum.sort() == [:checked_at, :next_check_at]
        assert DateTime.diff(changes.next_check_at, @now) == 300
      end

      assert %{next_check_at: _} =
               changes =
               DomainPolicy.after_check(
                 domain(%{}),
                 %{txt_ok: :unknown, routing_ok: true, tls_ok: false},
                 @now
               )

      refute Map.has_key?(changes, :status)
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

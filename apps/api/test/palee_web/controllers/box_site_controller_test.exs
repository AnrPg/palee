defmodule PaleeWeb.BoxSiteControllerTest do
  @moduledoc """
  ADR-352..354 end to end, as the RLS runtime role: staff set up the site,
  a visitor reads it, sends the forms and records a cookie choice, the
  outbox hands the lead over, and a custom domain goes from DNS to active.
  """

  use PaleeWeb.ConnCase, async: false

  import Palee.TestFixtures

  alias Palee.Application.{PublishBoxPublicProfile, UpdateBoxPublicProfile}
  alias Palee.Organizations
  alias Palee.Workers.BoxSiteJob

  setup do
    owner = admin_fixture()
    member = user_fixture()
    vendor = user_fixture()
    {:ok, _vendor} = Organizations.grant_vendor(vendor.id)

    {:ok, organization} =
      Organizations.create_organization(%{name: "Site Box #{System.unique_integer([:positive])}"})

    for {user, role} <- [{owner, :owner}, {member, :member}] do
      {:ok, _membership} =
        Organizations.add_membership(%{
          organization_id: organization.id,
          user_id: user.id,
          role: role,
          status: :active,
          joined_at: DateTime.utc_now()
        })
    end

    {:ok, context} = Organizations.resolve_tenant_context(owner, organization.slug)

    {:ok, profile} =
      UpdateBoxPublicProfile.call(context, %{"about" => "Box", "disciplines" => ["crossfit"]})

    {:ok, _profile} =
      PublishBoxPublicProfile.publish(context, %{"lock_version" => profile.lock_version})

    on_exit(fn ->
      Application.delete_env(:palee, :box_site_sandbox_dns)
      Application.delete_env(:palee, :box_site_sandbox_tls_ready)
    end)

    %{
      owner: owner,
      member: member,
      vendor: vendor,
      organization: organization,
      admin: "/api/org/#{organization.slug}/admin/site",
      public: "/api/public/sites/#{organization.slug}"
    }
  end

  defp owner_conn(ctx), do: put_bearer_token(build_conn(), ctx.owner)
  defp visitor, do: build_conn() |> put_req_header("content-type", "application/json")

  test "staff set the site; visitors see only what is public", ctx do
    # ADR-530: a new box starts on «Πλακίδια» with the timetable on.
    assert %{
             "settings" => %{
               "lock_version" => 0,
               "public_schedule" => true,
               "public_wod" => false,
               "template" => "tiles",
               "draft" => nil
             },
             "domains" => []
           } =
             ctx |> owner_conn() |> get(ctx.admin) |> json_response(200)

    token = String.duplicate("t", 40)

    settings =
      ctx
      |> owner_conn()
      |> put(ctx.admin, %{
        lock_version: 0,
        hidden_sections: ["coaches"],
        faq: [%{question: "Πού παρκάρω;", answer: "Στον δρόμο."}],
        meta_pixel_id: "123456789",
        ga4_measurement_id: "G-ABCD1234",
        conversions_api_enabled: true,
        conversions_api_token: token
      })
      |> json_response(200)
      |> Map.fetch!("settings")

    assert settings["has_conversions_api_token"]
    assert settings["banner_version"] == 2
    refute Map.has_key?(settings, "conversions_api_token")
    # The section switch waits for «Δημοσίευση».
    assert settings["draft"] == %{"hidden_sections" => ["coaches"]}
    assert settings["hidden_sections"] == []
    assert "coaches" in (build_conn() |> get(ctx.public) |> json_response(200))["sections"]

    assert %{"settings" => %{"draft" => nil, "hidden_sections" => ["coaches"]}} =
             ctx |> owner_conn() |> post("#{ctx.admin}/publish") |> json_response(200)

    assert %{"code" => "settings_changed_meanwhile"} =
             ctx
             |> owner_conn()
             |> put(ctx.admin, %{lock_version: 0, forms_enabled: false})
             |> json_response(409)

    site = build_conn() |> get(ctx.public) |> json_response(200)

    refute "coaches" in site["sections"]
    assert "schedule" in site["sections"]
    assert "faq" in site["sections"]
    assert [%{"question" => "Πού παρκάρω;", "answer" => "Στον δρόμο.", "id" => _id}] = site["faq"]
    assert site["tracking"]["consent_required"]
    assert site["tracking"]["tags"]["meta_pixel_id"] == "123456789"
    assert site["timetable"] == []
    refute inspect(site) =~ token

    assert %{"errors" => _} =
             ctx
             |> owner_conn()
             |> put(ctx.admin, %{lock_version: 1, gtm_container_id: "nope"})
             |> json_response(422)

    # Members cannot change the site.
    build_conn() |> put_bearer_token(ctx.member) |> get(ctx.admin) |> json_response(403)

    build_conn()
    |> get("/api/public/sites/nobody-#{System.unique_integer([:positive])}")
    |> json_response(404)
  end

  test "a visitor consents, sends the trial form and it becomes a lead", ctx do
    token = String.duplicate("t", 40)

    ctx
    |> owner_conn()
    |> put(ctx.admin, %{
      lock_version: 0,
      meta_pixel_id: "123456789",
      conversions_api_enabled: true,
      conversions_api_token: token
    })
    |> json_response(200)

    visitor = Ecto.UUID.generate()

    assert %{"allowed_tags" => ["meta_pixel_id"], "marketing" => true} =
             visitor()
             |> post("#{ctx.public}/consents", %{
               visitor_id: visitor,
               banner_version: 2,
               action: "accept_all"
             })
             |> json_response(201)

    assert %{"errors" => _} =
             visitor()
             |> post("#{ctx.public}/consents", %{
               visitor_id: visitor,
               banner_version: 1,
               action: "accept_all"
             })
             |> json_response(422)

    Process.put(:palee_conversions_probe, self())
    pixel_event_id = Ecto.UUID.generate()

    assert %{"status" => "received"} =
             visitor()
             |> post("#{ctx.public}/forms/trial", %{
               name: "Μαρία",
               email: "maria@example.gr",
               privacy_ack: true,
               visitor_id: visitor,
               event_id: pixel_event_id,
               elapsed_ms: 8_000,
               attribution: %{utm_source: "instagram"}
             })
             |> json_response(202)

    # A bot's post looks accepted and is dropped.
    assert %{"status" => "received"} =
             visitor()
             |> post("#{ctx.public}/forms/contact", %{
               name: "x",
               email: "x@y.zz",
               privacy_ack: true,
               website: "http://spam"
             })
             |> json_response(202)

    assert %{"errors" => _} =
             visitor()
             |> post("#{ctx.public}/forms/contact", %{name: "Νίκος", privacy_ack: false})
             |> json_response(422)

    # Without background jobs the outbox ran inline: delivered and redacted.
    rows =
      bypass_rls(fn ->
        Palee.Repo.query!(
          "SELECT status, name, email, lead_id, conversion_status, conversion_payload FROM box_site_submissions WHERE organization_id = $1",
          [Ecto.UUID.dump!(ctx.organization.id)]
        ).rows
      end)

    assert [["delivered", nil, nil, lead_id, "sent", nil]] = rows

    # The Conversions API event carries the browser Pixel's eventID (dedupe).
    assert_received {:conversion_event, %{"event_id" => ^pixel_event_id}}
    assert is_binary(lead_id)

    # ADR-388: the lead has no owner yet, so whoever handles «Ενδιαφερόμενοι»
    # hears about it (the owner here); never the member.
    notices =
      bypass_rls(fn ->
        Palee.Repo.query!(
          "SELECT user_id FROM notifications WHERE type = 'site_request' AND organization_id = $1",
          [Ecto.UUID.dump!(ctx.organization.id)]
        ).rows
      end)

    assert [[owner_id]] = notices
    assert Ecto.UUID.load!(owner_id) == ctx.owner.id

    assert %{
             "submissions" => %{"total" => 1, "delivered" => 1},
             "consents" => %{"accept_all" => 1}
           } =
             ctx |> owner_conn() |> get("#{ctx.admin}/summary") |> json_response(200)
  end

  test "forms can be closed and a lead the leads side rejects fails", ctx do
    ctx
    |> owner_conn()
    |> put(ctx.admin, %{lock_version: 0, forms_enabled: false})
    |> json_response(200)

    assert %{"code" => "site_forms_closed"} =
             visitor()
             |> post("#{ctx.public}/forms/trial", %{
               name: "Μαρία",
               email: "m@example.gr",
               privacy_ack: true
             })
             |> json_response(409)

    refute "trial_form" in (build_conn() |> get(ctx.public) |> json_response(200))["sections"]

    ctx
    |> owner_conn()
    |> put(ctx.admin, %{lock_version: 1, forms_enabled: true})
    |> json_response(200)

    visitor()
    |> post("#{ctx.public}/forms/trial", %{
      name: "reject me",
      email: "m@example.gr",
      privacy_ack: true
    })
    |> json_response(202)

    visitor()
    |> post("#{ctx.public}/forms/trial", %{
      name: "retry me",
      email: "r@example.gr",
      privacy_ack: true
    })
    |> json_response(202)

    statuses =
      bypass_rls(fn ->
        Palee.Repo.query!(
          "SELECT name, status FROM box_site_submissions WHERE organization_id = $1 ORDER BY name",
          [Ecto.UUID.dump!(ctx.organization.id)]
        ).rows
      end)

    assert statuses == [["reject me", "failed"], ["retry me", "pending"]]
  end

  test "a custom domain: DNS proof, routing, TLS, host lookup and ops list", ctx do
    assert %{"code" => "platform_hostname"} =
             ctx
             |> owner_conn()
             |> post("#{ctx.admin}/domains", %{host: "box.palee.app"})
             |> json_response(422)

    host = "www.site#{System.unique_integer([:positive])}.test"

    domain =
      ctx
      |> owner_conn()
      |> post("#{ctx.admin}/domains", %{host: "https://#{String.upcase(host)}/"})
      |> json_response(201)
      |> Map.fetch!("domain")

    assert %{
             "host" => ^host,
             "status" => "pending_dns",
             "primary" => true,
             "last_error" => "dns_txt_missing"
           } = domain

    assert [
             %{"type" => "TXT", "value" => txt},
             %{"type" => "CNAME", "value" => "sites.palee.app"}
           ] = domain["dns_records"]

    assert %{"code" => "host_taken"} =
             ctx
             |> owner_conn()
             |> post("#{ctx.admin}/domains", %{host: host})
             |> json_response(409)

    Application.put_env(:palee, :box_site_sandbox_dns, %{
      {"_palee-challenge." <> host, :txt} => [txt],
      {host, :cname} => ["sites.palee.app."]
    })

    assert %{"domain" => %{"status" => "pending_tls", "last_error" => "tls_not_ready"}} =
             ctx
             |> owner_conn()
             |> post("#{ctx.admin}/domains/#{domain["id"]}/check")
             |> json_response(200)

    assert %{"allowed" => true} =
             build_conn()
             |> get("/api/public/sites/tls-allowed?domain=#{host}")
             |> json_response(200)

    build_conn() |> get("/api/public/sites/tls-allowed?domain=unknown.test") |> json_response(404)

    assert %{"domains" => [%{"host" => ^host, "status" => "pending_tls"} | _]} =
             build_conn()
             |> put_bearer_token(ctx.vendor)
             |> get("/api/platform/site-domains?status=pending_tls")
             |> json_response(200)
             |> Map.update!("domains", fn list -> Enum.filter(list, &(&1["host"] == host)) end)

    Application.put_env(:palee, :box_site_sandbox_tls_ready, [host])

    assert %{"domain" => %{"status" => "active", "last_error" => nil}} =
             ctx
             |> owner_conn()
             |> post("#{ctx.admin}/domains/#{domain["id"]}/check")
             |> json_response(200)

    assert %{"slug" => slug, "primary_host" => ^host} =
             build_conn() |> get("/api/public/sites/by-host/#{host}") |> json_response(200)

    assert slug == ctx.organization.slug

    assert (build_conn() |> get(ctx.public) |> json_response(200))["canonical_url"] ==
             "https://" <> host

    # DNS gone: the cron job marks it broken; the lookup keeps serving.
    Application.put_env(:palee, :box_site_sandbox_dns, %{})

    bypass_rls(fn ->
      Palee.Repo.query!(
        "UPDATE box_site_domains SET next_check_at = now() - interval '1 minute' WHERE host = $1",
        [host]
      )
    end)

    assert :ok = perform_job(BoxSiteJob, %{})

    assert [%{"status" => "broken", "last_error" => "dns_not_pointing"}] =
             ctx
             |> owner_conn()
             |> get("#{ctx.admin}/domains")
             |> json_response(200)
             |> Map.fetch!("domains")

    build_conn() |> get("/api/public/sites/by-host/#{host}") |> json_response(200)

    second = "shop.#{String.replace_prefix(host, "www.", "")}"

    %{"domain" => %{"id" => second_id, "primary" => false}} =
      ctx |> owner_conn() |> post("#{ctx.admin}/domains", %{host: second}) |> json_response(201)

    assert %{"code" => "too_many_domains"} =
             ctx
             |> owner_conn()
             |> post("#{ctx.admin}/domains", %{host: "x." <> second})
             |> json_response(409)

    assert %{"domain" => %{"primary" => true}} =
             ctx
             |> owner_conn()
             |> put("#{ctx.admin}/domains/#{second_id}/primary")
             |> json_response(200)

    ctx |> owner_conn() |> delete("#{ctx.admin}/domains/#{domain["id"]}") |> response(204)
    ctx |> owner_conn() |> delete("#{ctx.admin}/domains/#{domain["id"]}") |> json_response(404)
    build_conn() |> get("/api/public/sites/by-host/#{host}") |> json_response(404)
  end

  defmodule RecordingIngress do
    @moduledoc "ADR-398: the sandbox cluster, telling the test process what it was asked."
    @behaviour Palee.BoxSite.Ports.SiteIngress
    alias Palee.Infrastructure.BoxSite.SandboxSiteIngress

    @impl true
    def apply_site(host), do: tell({:apply, host}, SandboxSiteIngress.apply_site(host))
    @impl true
    def remove_site(host), do: tell({:remove, host}, SandboxSiteIngress.remove_site(host))
    @impl true
    def certificate(host), do: tell({:certificate, host}, SandboxSiteIngress.certificate(host))
    @impl true
    def managed_hosts, do: SandboxSiteIngress.managed_hosts()

    defp tell(message, answer) do
      send(self(), {:ingress, message})
      answer
    end
  end

  defp flush_ingress_calls do
    receive do
      {:ingress, _call} -> flush_ingress_calls()
    after
      0 -> :ok
    end
  end

  test "ADR-398: a verified host gets its Ingress and certificate; removal deletes it", ctx do
    previous = Application.get_env(:palee, :box_site_ingress)
    Application.put_env(:palee, :box_site_ingress, RecordingIngress)

    on_exit(fn ->
      Application.put_env(:palee, :box_site_ingress, previous)
      Application.delete_env(:palee, :box_site_sandbox_certificates)
      Application.delete_env(:palee, :box_site_sandbox_ingress_refused)
      Application.delete_env(:palee, :box_site_sandbox_managed_hosts)
    end)

    host = "www.certs#{System.unique_integer([:positive])}.test"

    domain =
      ctx
      |> owner_conn()
      |> post("#{ctx.admin}/domains", %{host: host})
      |> json_response(201)
      |> Map.fetch!("domain")

    # No DNS proof yet: no Ingress, nothing to say about the certificate.
    assert %{"certificate_status" => "none", "certificate_error" => nil} = domain
    refute_received {:ingress, _call}

    [txt | _cname] = Enum.map(domain["dns_records"], & &1["value"])

    Application.put_env(:palee, :box_site_sandbox_dns, %{
      {"_palee-challenge." <> host, :txt} => [txt],
      {host, :cname} => ["sites.palee.app."]
    })

    # Proven: the Ingress is applied at once and the certificate is issuing.
    assert %{"domain" => %{"status" => "pending_tls", "certificate_status" => "issuing"}} =
             ctx
             |> owner_conn()
             |> post("#{ctx.admin}/domains/#{domain["id"]}/check")
             |> json_response(200)

    assert_received {:ingress, {:apply, ^host}}

    # cert-manager gave up for now: the card shows a plain reason.
    Application.put_env(:palee, :box_site_sandbox_certificates, %{
      host => {:failed, :challenge_failed}
    })

    assert %{
             "domain" => %{
               "certificate_status" => "failed",
               "certificate_error" => "challenge_failed"
             }
           } =
             ctx
             |> owner_conn()
             |> post("#{ctx.admin}/domains/#{domain["id"]}/check")
             |> json_response(200)

    refute_received {:ingress, {:apply, _host}}

    Application.put_env(:palee, :box_site_sandbox_certificates, %{host => :active})
    Application.put_env(:palee, :box_site_sandbox_tls_ready, [host])

    assert %{
             "domain" => %{
               "status" => "active",
               "certificate_status" => "active",
               "certificate_error" => nil
             }
           } =
             ctx
             |> owner_conn()
             |> post("#{ctx.admin}/domains/#{domain["id"]}/check")
             |> json_response(200)

    # An active certificate is not read on every check, only by the nightly sweep.
    flush_ingress_calls()

    assert %{"domain" => %{"certificate_status" => "active"}} =
             ctx
             |> owner_conn()
             |> post("#{ctx.admin}/domains/#{domain["id"]}/check")
             |> json_response(200)

    refute_received {:ingress, {:certificate, ^host}}

    # The sweep removes an Ingress no box has and restores a missing one.
    Application.put_env(:palee, :box_site_sandbox_managed_hosts, ["gone.example"])
    assert :ok = perform_job(Palee.Workers.BoxSiteIngressSweepJob, %{})
    assert_received {:ingress, {:remove, "gone.example"}}
    assert_received {:ingress, {:apply, ^host}}

    # ... and rereads the active certificates of the Ingresses it found.
    Application.put_env(:palee, :box_site_sandbox_managed_hosts, [host])

    Application.put_env(:palee, :box_site_sandbox_certificates, %{
      host => {:failed, :rate_limited}
    })

    assert :ok = perform_job(Palee.Workers.BoxSiteIngressSweepJob, %{})
    assert_received {:ingress, {:certificate, ^host}}

    assert [%{"certificate_status" => "failed", "certificate_error" => "rate_limited"}] =
             ctx
             |> owner_conn()
             |> get("#{ctx.admin}/domains")
             |> json_response(200)
             |> Map.fetch!("domains")

    ctx |> owner_conn() |> delete("#{ctx.admin}/domains/#{domain["id"]}") |> response(204)
    assert_received {:ingress, {:remove, ^host}}

    assert [] =
             bypass_rls(fn ->
               Palee.Repo.query!("SELECT 1 FROM box_site_ingress_ops WHERE host = $1", [host]).rows
             end)
  end

  test "ADR-398: a cluster that refuses keeps the op for a retry and says so", ctx do
    previous = Application.get_env(:palee, :box_site_ingress)
    Application.put_env(:palee, :box_site_ingress, RecordingIngress)
    host = "www.refused#{System.unique_integer([:positive])}.test"
    Application.put_env(:palee, :box_site_sandbox_ingress_refused, [host])

    on_exit(fn ->
      Application.put_env(:palee, :box_site_ingress, previous)
      Application.delete_env(:palee, :box_site_sandbox_ingress_refused)
    end)

    domain =
      ctx
      |> owner_conn()
      |> post("#{ctx.admin}/domains", %{host: host})
      |> json_response(201)
      |> Map.fetch!("domain")

    [txt | _cname] = Enum.map(domain["dns_records"], & &1["value"])

    Application.put_env(:palee, :box_site_sandbox_dns, %{
      {"_palee-challenge." <> host, :txt} => [txt],
      {host, :cname} => ["sites.palee.app."]
    })

    assert %{
             "domain" => %{
               "certificate_status" => "pending",
               "certificate_error" => "cluster_refused"
             }
           } =
             ctx
             |> owner_conn()
             |> post("#{ctx.admin}/domains/#{domain["id"]}/check")
             |> json_response(200)

    assert [["pending", 1, "cluster_refused"]] =
             bypass_rls(fn ->
               Palee.Repo.query!(
                 "SELECT status, attempts, last_error FROM box_site_ingress_ops WHERE host = $1",
                 [host]
               ).rows
             end)

    # The cluster is set up: the due op goes through on the next run.
    Application.delete_env(:palee, :box_site_sandbox_ingress_refused)

    bypass_rls(fn ->
      Palee.Repo.query!(
        "UPDATE box_site_ingress_ops SET next_attempt_at = now() - interval '1 minute' WHERE host = $1",
        [host]
      )
    end)

    assert :ok = perform_job(BoxSiteJob, %{})
    assert_received {:ingress, {:apply, ^host}}

    assert [%{"certificate_status" => "issuing", "certificate_error" => nil}] =
             ctx
             |> owner_conn()
             |> get("#{ctx.admin}/domains")
             |> json_response(200)
             |> Map.fetch!("domains")
  end

  test "ADR-398: system domains are refused when they are typed", ctx do
    for host <- ~w(milos.4kq.net www.atha.gr atha.io palee.app shop.palee.app) do
      assert %{"code" => "platform_hostname"} =
               ctx
               |> owner_conn()
               |> post("#{ctx.admin}/domains", %{host: host})
               |> json_response(422)
    end
  end

  test "ADR-398: a flattened apex passes on the target's live addresses", ctx do
    host = "apex#{System.unique_integer([:positive])}.test"

    domain =
      ctx
      |> owner_conn()
      |> post("#{ctx.admin}/domains", %{host: String.upcase(host)})
      |> json_response(201)
      |> Map.fetch!("domain")

    assert %{"host" => ^host} = domain

    assert [
             %{"type" => "TXT", "value" => txt},
             %{"type" => "ALIAS", "name" => ^host, "value" => "sites.palee.app"}
           ] = domain["dns_records"]

    check = fn ->
      ctx
      |> owner_conn()
      |> post("#{ctx.admin}/domains/#{domain["id"]}/check")
      |> json_response(200)
      |> Map.fetch!("domain")
    end

    # A fixed address that is not the target's (any more) does not pass.
    Application.put_env(:palee, :box_site_sandbox_dns, %{
      {"_palee-challenge." <> host, :txt} => [txt],
      {host, :a} => ["203.0.113.9"]
    })

    assert %{"status" => "pending_dns", "last_error" => "dns_not_pointing"} = check.()

    # The resolver timing out says nothing: the host keeps its state.
    Application.put_env(:palee, :box_site_sandbox_dns, %{
      {"_palee-challenge." <> host, :txt} => [txt],
      {host, :cname} => {:error, :timeout},
      {host, :a} => {:error, :timeout}
    })

    assert %{"status" => "pending_dns", "last_error" => "dns_not_pointing"} = check.()

    Application.put_env(:palee, :box_site_sandbox_dns, %{
      {"_palee-challenge." <> host, :txt} => [txt],
      {host, :a} => [Palee.Infrastructure.BoxSite.SandboxDomainDns.target_address()]
    })

    assert %{"status" => "pending_tls"} = check.()
  end

  test "ADR-398: a resolver error never deletes a verified host's Ingress", ctx do
    previous = Application.get_env(:palee, :box_site_ingress)
    Application.put_env(:palee, :box_site_ingress, RecordingIngress)
    on_exit(fn -> Application.put_env(:palee, :box_site_ingress, previous) end)
    host = "www.flaky#{System.unique_integer([:positive])}.test"

    domain =
      ctx |> owner_conn() |> post("#{ctx.admin}/domains", %{host: host}) |> json_response(201)

    [txt | _cname] = Enum.map(domain["domain"]["dns_records"], & &1["value"])

    Application.put_env(:palee, :box_site_sandbox_dns, %{
      {"_palee-challenge." <> host, :txt} => [txt],
      {host, :cname} => ["sites.palee.app."]
    })

    check = fn ->
      ctx
      |> owner_conn()
      |> post("#{ctx.admin}/domains/#{domain["domain"]["id"]}/check")
      |> json_response(200)
      |> Map.fetch!("domain")
    end

    assert %{"status" => "pending_tls"} = check.()
    assert_received {:ingress, {:apply, ^host}}

    Application.put_env(:palee, :box_site_sandbox_dns, %{
      {"_palee-challenge." <> host, :txt} => {:error, :timeout},
      {host, :cname} => {:error, :servfail},
      {host, :a} => {:error, :servfail}
    })

    assert %{"status" => "pending_tls", "certificate_status" => "issuing"} = check.()
    refute_received {:ingress, {:remove, _host}}

    # A real answer that no longer points here still takes it back.
    Application.put_env(:palee, :box_site_sandbox_dns, %{})
    assert %{"status" => "pending_dns", "certificate_status" => "none"} = check.()
    assert_received {:ingress, {:remove, ^host}}
  end

  test "ADR-398: a host the cluster's policy refuses is final and says so", ctx do
    previous = Application.get_env(:palee, :box_site_ingress)
    Application.put_env(:palee, :box_site_ingress, RecordingIngress)
    host = "www.taken#{System.unique_integer([:positive])}.test"
    Application.put_env(:palee, :box_site_sandbox_ingress_not_allowed, [host])

    on_exit(fn ->
      Application.put_env(:palee, :box_site_ingress, previous)
      Application.delete_env(:palee, :box_site_sandbox_ingress_not_allowed)
      Application.delete_env(:palee, :box_site_sandbox_managed_hosts)
    end)

    domain =
      ctx
      |> owner_conn()
      |> post("#{ctx.admin}/domains", %{host: host})
      |> json_response(201)
      |> Map.fetch!("domain")

    [txt | _cname] = Enum.map(domain["dns_records"], & &1["value"])

    Application.put_env(:palee, :box_site_sandbox_dns, %{
      {"_palee-challenge." <> host, :txt} => [txt],
      {host, :cname} => ["sites.palee.app."]
    })

    check = fn ->
      ctx
      |> owner_conn()
      |> post("#{ctx.admin}/domains/#{domain["id"]}/check")
      |> json_response(200)
      |> Map.fetch!("domain")
    end

    assert %{"certificate_status" => "failed", "certificate_error" => "host_not_allowed"} =
             check.()

    assert_received {:ingress, {:apply, ^host}}

    # One try, no retry loop.
    assert [["failed", 1, "host_not_allowed"]] =
             bypass_rls(fn ->
               Palee.Repo.query!(
                 "SELECT status, attempts, last_error FROM box_site_ingress_ops WHERE host = $1",
                 [host]
               ).rows
             end)

    # Neither «Έλεγχος τώρα», the cron nor the sweep tries again.
    assert %{"certificate_error" => "host_not_allowed"} = check.()
    assert :ok = perform_job(BoxSiteJob, %{})
    Application.put_env(:palee, :box_site_sandbox_managed_hosts, [])
    assert :ok = perform_job(Palee.Workers.BoxSiteIngressSweepJob, %{})
    refute_received {:ingress, {:apply, ^host}}

    # Removing it and adding it again is a fresh start.
    ctx |> owner_conn() |> delete("#{ctx.admin}/domains/#{domain["id"]}") |> response(204)

    assert %{"domain" => %{"certificate_status" => "none", "certificate_error" => nil}} =
             ctx
             |> owner_conn()
             |> post("#{ctx.admin}/domains", %{host: host})
             |> json_response(201)
  end

  test "ADR-553: the «Πακέτα» section follows who sees the packages", ctx do
    {:ok, context} = Organizations.resolve_tenant_context(ctx.owner, ctx.organization.slug)
    sections = fn -> (build_conn() |> get(ctx.public) |> json_response(200))["sections"] end
    audience = "/api/org/#{ctx.organization.slug}/admin/package-audience"

    refute "packages" in sections.()

    {:ok, package} =
      Palee.Finance.create_package(context, %{
        name: "Μηνιαίο",
        family: "unlimited",
        billing_period: "monthly",
        base_price_cents: 6_000
      })

    assert "packages" in sections.()

    ctx |> owner_conn() |> put(audience, %{audience: "none"}) |> json_response(200)
    refute "packages" in sections.()

    ctx
    |> owner_conn()
    |> put("#{audience}/packages/#{package.id}", %{audience: "all"})
    |> json_response(200)

    assert "packages" in sections.()

    # The website no longer hides it by itself: the box's choice decides.
    ctx
    |> owner_conn()
    |> put(ctx.admin, %{lock_version: 0, hidden_sections: ["packages"]})
    |> json_response(200)

    ctx |> owner_conn() |> post("#{ctx.admin}/publish") |> json_response(200)
    assert "packages" in sections.()
  end

  test "the public timetable shows classes without people when the owner turns it on", ctx do
    ctx
    |> owner_conn()
    |> put(ctx.admin, %{lock_version: 0, public_schedule: true})
    |> json_response(200)

    site = build_conn() |> get(ctx.public) |> json_response(200)
    assert "schedule" in site["sections"]
    assert is_list(site["timetable"])
  end

  test "ADR-388: events and WOD sections and the site's languages", ctx do
    site = build_conn() |> get(ctx.public) |> json_response(200)
    # WOD stays off until the owner turns it on; events show when there are any.
    assert "events" in site["sections"]
    refute "wod" in site["sections"]
    assert %{"language" => language, "languages" => [language | _], "time_zone" => _zone} = site
    assert site["about"] == nil and site["translation"] == nil and site["texts"] == %{}
    assert site["events"] == [] and site["wod"] == []

    ctx
    |> owner_conn()
    |> put(ctx.admin, %{lock_version: 0, public_wod: true})
    |> json_response(200)

    refute "wod" in (build_conn() |> get(ctx.public) |> json_response(200))["sections"]
    ctx |> owner_conn() |> post("#{ctx.admin}/publish") |> json_response(200)

    assert "wod" in (build_conn() |> get(ctx.public) |> json_response(200))["sections"]
  end

  describe "ADR-520: translations of the website" do
    setup ctx do
      greek_box(ctx.organization)
      :ok
    end

    test "the owner picks languages; the box's own and unknown ones are refused", ctx do
      %{"languages" => languages, "settings" => settings} =
        ctx |> owner_conn() |> get(ctx.admin) |> json_response(200)

      assert languages["source"] == "el"
      refute "el" in languages["available"]
      assert "en" in languages["available"] and "pt-PT" in languages["available"]
      assert settings["translation_locales"] == ["en"] and settings["visible_locales"] == ["en"]
      assert [%{"locale" => "en", "total" => total}] = languages["progress"]
      assert total >= 1

      assert %{
               "settings" => %{"translation_locales" => ["en", "de"], "visible_locales" => ["en"]}
             } =
               ctx
               |> owner_conn()
               |> put(ctx.admin, %{
                 lock_version: 0,
                 translation_locales: ["en", "el", "DE", "en"],
                 visible_locales: ["en", "de-xx"]
               })
               |> json_response(422)
               |> then(fn _refused ->
                 ctx
                 |> owner_conn()
                 |> put(ctx.admin, %{
                   lock_version: 0,
                   translation_locales: ["en", "el", "DE", "en"],
                   visible_locales: ["en"]
                 })
                 |> json_response(200)
               end)

      site = build_conn() |> get(ctx.public) |> json_response(200)
      assert site["languages"] == ["el", "en"]
    end

    test "every text of the site, side by side, with its status", ctx do
      %{"settings" => %{"lock_version" => lock}} =
        ctx
        |> owner_conn()
        |> put(ctx.admin, %{
          lock_version: 0,
          faq: [%{question: "Πού παρκάρω;", answer: "Στην πλατεία."}]
        })
        |> json_response(200)

      page =
        ctx |> owner_conn() |> get("#{ctx.admin}/translations?locale=en") |> json_response(200)

      assert page["locale"] == "en" and page["source_language"] == "el"
      assert page["counts"] == %{"missing" => 3, "stale" => 0, "machine" => 0, "ok" => 0}

      assert [about, question, answer] = page["items"]

      assert %{
               "group" => "about",
               "kind" => "box_profile",
               "source" => "Box",
               "status" => "missing"
             } = about

      assert %{"group" => "faq", "field" => "question", "label" => "1"} = question
      assert answer["source"] == "Στην πλατεία."

      # A person writes two texts; an empty one is no translation.
      page =
        ctx
        |> owner_conn()
        |> put("#{ctx.admin}/translations", %{
          locale: "en",
          entries: [
            %{
              kind: "site_faq",
              id: question["id"],
              field: "question",
              text: " Where do I park? "
            },
            %{kind: "site_faq", id: answer["id"], field: "answer", text: "On the square."},
            %{kind: "box_profile", id: about["id"], field: "about", text: ""}
          ]
        })
        |> json_response(200)

      assert page["counts"]["ok"] == 2 and page["counts"]["missing"] == 1

      # The box's own language and unknown texts are refused.
      ctx
      |> owner_conn()
      |> get("#{ctx.admin}/translations?locale=el")
      |> json_response(422)

      ctx
      |> owner_conn()
      |> put("#{ctx.admin}/translations", %{
        locale: "en",
        entries: [%{kind: "event", id: Ecto.UUID.generate(), field: "title", text: "Hi"}]
      })
      |> json_response(422)

      # The visitor reads the English site.
      site = build_conn() |> get("#{ctx.public}?lang=EN") |> json_response(200)
      assert site["translation"] == "en"
      assert [%{"question" => "Where do I park?", "answer" => "On the square."}] = site["faq"]
      assert site["about"] == nil

      greek = build_conn() |> get(ctx.public) |> json_response(200)
      assert [%{"question" => "Πού παρκάρω;"}] = greek["faq"]

      # The owner changes the Greek answer: its translation is out of date, still shown.
      [entry] = greek["faq"]

      ctx
      |> owner_conn()
      |> put(ctx.admin, %{
        lock_version: lock,
        faq: [%{id: entry["id"], question: "Πού παρκάρω;", answer: "Στην πλατεία, δωρεάν."}]
      })
      |> json_response(200)

      page =
        ctx |> owner_conn() |> get("#{ctx.admin}/translations?locale=en") |> json_response(200)

      assert %{"stale" => 1, "ok" => 1} = page["counts"]

      assert [%{"answer" => "On the square."}] =
               (build_conn() |> get("#{ctx.public}?lang=en") |> json_response(200))["faq"]

      # «Αυτόματη μετάφραση» fills the missing and stale ones, never the person's current text.
      page =
        ctx
        |> owner_conn()
        |> post("#{ctx.admin}/translations/machine", %{locale: "en"})
        |> json_response(200)

      assert page["written"] == 2
      assert %{"machine" => 2, "ok" => 1, "missing" => 0, "stale" => 0} = page["counts"]
      by_field = Map.new(page["items"], &{&1["field"], &1})
      assert by_field["question"]["text"] == "Where do I park?"
      assert by_field["answer"]["text"] == "[EN] Στην πλατεία, δωρεάν."
      assert by_field["about"]["origin"] == "machine"

      # «Εντάξει, κράτα το».
      page =
        ctx
        |> owner_conn()
        |> post("#{ctx.admin}/translations/keep", %{
          locale: "en",
          keys: [by_field["answer"]["key"]]
        })
        |> json_response(200)

      assert %{"machine" => 1, "ok" => 2} = page["counts"]

      # Hidden language: the visitor gets the box's own texts.
      ctx
      |> owner_conn()
      |> put(ctx.admin, %{
        lock_version: lock + 1,
        visible_locales: [],
        translation_locales: ["en"]
      })
      |> json_response(200)

      hidden = build_conn() |> get("#{ctx.public}?lang=en") |> json_response(200)
      assert hidden["translation"] == nil and hidden["languages"] == ["el"]
      assert [%{"answer" => "Στην πλατεία, δωρεάν."}] = hidden["faq"]
    end

    test "machine translation that is not set up says so", ctx do
      Application.put_env(:palee, :content_sandbox_translation, :unavailable)
      on_exit(fn -> Application.delete_env(:palee, :content_sandbox_translation) end)

      %{"languages" => %{"machine_available" => false}} =
        ctx |> owner_conn() |> get(ctx.admin) |> json_response(200)

      ctx
      |> owner_conn()
      |> post("#{ctx.admin}/translations/machine", %{locale: "en"})
      |> json_response(503)
    end

    test "another box never reads these translations", ctx do
      other = admin_fixture()

      {:ok, organization} =
        Organizations.create_organization(%{name: "Other #{System.unique_integer([:positive])}"})

      {:ok, _membership} =
        Organizations.add_membership(%{
          organization_id: organization.id,
          user_id: other.id,
          role: :owner,
          status: :active,
          joined_at: DateTime.utc_now()
        })

      greek_box(organization)

      page =
        ctx |> owner_conn() |> get("#{ctx.admin}/translations?locale=en") |> json_response(200)

      [about] = page["items"]

      ctx
      |> owner_conn()
      |> put("#{ctx.admin}/translations", %{
        locale: "en",
        entries: [%{kind: "box_profile", id: about["id"], field: "about", text: "Box EN"}]
      })
      |> json_response(200)

      other_page =
        build_conn()
        |> put_bearer_token(other)
        |> get("/api/org/#{organization.slug}/admin/site/translations?locale=en")
        |> json_response(200)

      assert other_page["items"] == []
    end
  end

  defp greek_box(organization) do
    import Ecto.Query

    {1, _rows} =
      bypass_rls(fn ->
        Palee.Repo.update_all(
          from(s in Palee.Organizations.OrganizationSetting,
            where: s.organization_id == ^organization.id
          ),
          set: [default_locale: "el"]
        )
      end)
  end

  test "ADR-388: «Στείλε τις οδηγίες» emails the records with a status link", ctx do
    host = "www.instr#{System.unique_integer([:positive])}.test"

    %{"domain" => %{"id" => id}} =
      ctx
      |> owner_conn()
      |> post("#{ctx.admin}/domains", %{host: host})
      |> json_response(201)

    assert %{"errors" => _} =
             ctx
             |> owner_conn()
             |> post("#{ctx.admin}/domains/#{id}/instructions", %{email: "not an address"})
             |> json_response(422)

    conn =
      ctx
      |> owner_conn()
      |> post("#{ctx.admin}/domains/#{id}/instructions", %{email: "Web@Example.gr"})

    # A new business is in demo mode (ADR-184): nothing leaves.
    case conn.status do
      200 ->
        assert %{"sent_to" => "web@example.gr"} = json_response(conn, 200)

      403 ->
        assert %{"code" => "business_not_activated"} = json_response(conn, 403)
    end

    token =
      Palee.Application.SignedToken.sign("box-site-domain-status", %{
        "o" => ctx.organization.id,
        "d" => id
      })

    assert %{"host" => ^host, "status" => "pending_dns", "dns_records" => [_txt, _cname]} =
             build_conn()
             |> get("/api/public/sites/domain-status/#{token}")
             |> json_response(200)

    build_conn() |> get("/api/public/sites/domain-status/forged") |> json_response(404)

    ctx
    |> owner_conn()
    |> post("#{ctx.admin}/domains/#{Ecto.UUID.generate()}/instructions", %{email: "a@b.gr"})
    |> json_response(404)
  end

  defp perform_job(worker, args), do: worker.perform(%Oban.Job{args: args})
end

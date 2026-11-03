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
    assert %{"settings" => %{"lock_version" => 0, "public_schedule" => false}, "domains" => []} =
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

    assert %{"code" => "settings_changed_meanwhile"} =
             ctx
             |> owner_conn()
             |> put(ctx.admin, %{lock_version: 0, forms_enabled: false})
             |> json_response(409)

    site = build_conn() |> get(ctx.public) |> json_response(200)

    refute "coaches" in site["sections"]
    refute "schedule" in site["sections"]
    assert "faq" in site["sections"]
    assert site["faq"] == [%{"question" => "Πού παρκάρω;", "answer" => "Στον δρόμο."}]
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

    assert %{"status" => "received"} =
             visitor()
             |> post("#{ctx.public}/forms/trial", %{
               name: "Μαρία",
               email: "maria@example.gr",
               privacy_ack: true,
               visitor_id: visitor,
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

  test "the public timetable shows classes without people when the owner turns it on", ctx do
    ctx
    |> owner_conn()
    |> put(ctx.admin, %{lock_version: 0, public_schedule: true})
    |> json_response(200)

    site = build_conn() |> get(ctx.public) |> json_response(200)
    assert "schedule" in site["sections"]
    assert is_list(site["timetable"])
  end

  test "ADR-388: events and WOD sections, English texts and the site's languages", ctx do
    site = build_conn() |> get(ctx.public) |> json_response(200)
    # WOD stays off until the owner turns it on; events show when there are any.
    assert "events" in site["sections"]
    refute "wod" in site["sections"]
    assert %{"language" => language, "languages" => languages, "time_zone" => _zone} = site
    assert "en" in languages and language in languages
    assert site["about_en"] == nil
    assert site["events"] == [] and site["wod"] == []

    assert %{"errors" => _} =
             ctx
             |> owner_conn()
             |> put(ctx.admin, %{lock_version: 0, about_en: String.duplicate("a", 4001)})
             |> json_response(422)

    assert %{"settings" => %{"public_wod" => true, "about_en" => "We train every day."}} =
             ctx
             |> owner_conn()
             |> put(ctx.admin, %{
               lock_version: 0,
               public_wod: true,
               about_en: "  We train every day. ",
               faq: [
                 %{
                   question: "Πού παρκάρω;",
                   answer: "Στην πλατεία.",
                   question_en: "Where do I park?",
                   answer_en: "On the square."
                 },
                 %{question: "Χρειάζομαι εμπειρία;", answer: "Όχι.", question_en: "Experience?"}
               ]
             })
             |> json_response(200)

    site = build_conn() |> get(ctx.public) |> json_response(200)
    assert "wod" in site["sections"]
    assert site["about_en"] == "We train every day."

    # The English half shows only when both are there.
    assert [%{"question_en" => "Where do I park?", "answer_en" => "On the square."}, second] =
             site["faq"]

    refute Map.has_key?(second, "question_en")
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

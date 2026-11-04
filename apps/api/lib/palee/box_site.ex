defmodule Palee.BoxSite do
  @moduledoc """
  The BoxSite bounded context (ADR-352..354): a box's website built from the
  data it already has.

    * settings: section order, hidden sections, the public timetable switch,
      FAQ, forms, the box's tag ids and the optional Conversions API;
    * custom domains with DNS proof and TLS readiness;
    * the form outbox to the leads context (`Ports.LeadIntake`);
    * the consent log behind every tag.

  BoxSite never reads other contexts' tables; composing the public page,
  packages, schedule and the Google review link lives in
  `Palee.Application.BoxSite.*`.
  """

  alias Palee.BoxSite.BoxSiteStore

  alias Palee.BoxSite.Domain.{
    ConsentPolicy,
    ConversionEvent,
    DomainPolicy,
    FormPolicy,
    Hostname,
    SiteSections,
    SiteSettingsPolicy,
    TenantDataPolicy
  }

  # ── Ports and configuration ─────────────────────────────────────────────

  @doc "The configured clock (`BoxSite.Ports.Clock`)."
  def clock, do: Application.fetch_env!(:palee, :box_site_clock)
  @doc "The configured lead intake (`BoxSite.Ports.LeadIntake`)."
  def lead_intake, do: Application.fetch_env!(:palee, :box_site_lead_intake)
  @doc "The configured DNS adapter (`BoxSite.Ports.DomainDns`)."
  def dns, do: Application.fetch_env!(:palee, :box_site_dns)
  @doc "The configured TLS probe (`BoxSite.Ports.TlsProbe`)."
  def tls_probe, do: Application.fetch_env!(:palee, :box_site_tls_probe)
  @doc "The configured Conversions API (`BoxSite.Ports.ConversionsApi`)."
  def conversions_api, do: Application.fetch_env!(:palee, :box_site_conversions_api)

  defp domain_config, do: Application.get_env(:palee, :box_site, [])

  @doc "Where a custom host's CNAME must point."
  def cname_target, do: Keyword.get(domain_config(), :cname_target, "sites.palee.app")
  @doc "The A records an apex host must have (the ingress addresses)."
  def a_records, do: Keyword.get(domain_config(), :a_records, [])
  defp refused_suffixes, do: Keyword.get(domain_config(), :refused_suffixes, ["palee.app"])

  # ── Settings ────────────────────────────────────────────────────────────

  @doc "The box's settings, or the defaults when it never saved any."
  def settings(context) do
    case BoxSiteStore.get_settings(context) do
      nil -> SiteSettingsPolicy.defaults()
      settings -> Map.update!(settings, :section_order, &SiteSections.normalize_order/1)
    end
  end

  @doc """
  Saves an edit (string keys) against `lock_version` (0 for a box that never
  saved). `{:error, :stale}` when someone saved meanwhile.
  """
  def update_settings(context, params, user_id) do
    current = settings(context)

    with {:ok, changes} <- SiteSettingsPolicy.changes(current, params) do
      changes =
        changes
        |> maybe_wrap_faq()
        |> Map.put(:updated_by_id, user_id)

      lock = Map.get(params, "lock_version", current.lock_version)

      case BoxSiteStore.save_settings(context, changes, lock) do
        {:ok, settings} ->
          {:ok, Map.update!(settings, :section_order, &SiteSections.normalize_order/1)}

        {:error, :stale} ->
          {:error, :settings_changed_meanwhile}

        error ->
          error
      end
    end
  end

  @doc """
  ADR-530 «Δημοσίευση»: the draft goes live (also without one: the notice of
  a moved site is then hidden and `published_at` stamped).
  """
  def publish(context, user_id) do
    current = settings(context)
    save_quietly(context, current, SiteSettingsPolicy.publish(current, clock().now()), user_id)
  end

  @doc "ADR-530 «Απόρριψη αλλαγών»: throws the draft away."
  def discard_draft(context, user_id) do
    current = settings(context)

    if is_nil(current.draft),
      do: {:ok, current},
      else: save_quietly(context, current, %{draft: nil}, user_id)
  end

  @doc "ADR-530: hides «Η ιστοσελίδα σου πήρε νέα όψη»."
  def dismiss_template_notice(context, user_id) do
    current = settings(context)

    if current.template_notice,
      do: save_quietly(context, current, %{template_notice: false}, user_id),
      else: {:ok, current}
  end

  defp save_quietly(context, current, changes, user_id) do
    changes = Map.put(changes, :updated_by_id, user_id)

    case BoxSiteStore.save_settings(context, changes, current.lock_version) do
      {:ok, settings} ->
        {:ok, Map.update!(settings, :section_order, &SiteSections.normalize_order/1)}

      {:error, :stale} ->
        {:error, :settings_changed_meanwhile}

      error ->
        error
    end
  end

  @doc "The settings with the draft applied (ADR-530 preview)."
  def drafted_settings(context), do: context |> settings() |> SiteSettingsPolicy.drafted()

  defdelegate templates(), to: SiteSettingsPolicy
  defdelegate palettes(), to: SiteSettingsPolicy
  defdelegate appearances(), to: SiteSettingsPolicy

  @doc """
  ADR-530: the live boxes whose site the migration moved to «Αρένα» and whose
  staff were not told yet (never a demo business).
  """
  defdelegate template_notices_due(), to: BoxSiteStore

  @doc "Marks the box's one-off notice as sent; `true` only for the caller that marked it."
  defdelegate claim_template_notice(context, now), to: BoxSiteStore

  # ADR-520: a new FAQ entry gets its stable id here.
  defp maybe_wrap_faq(%{faq: entries} = changes) do
    entries = Enum.map(entries, &Map.put_new_lazy(&1, "id", fn -> Ecto.UUID.generate() end))
    %{changes | faq: %{"entries" => entries}}
  end

  defp maybe_wrap_faq(changes), do: changes

  defdelegate conversions_api_token(context), to: BoxSiteStore
  defdelegate visible_sections(order, hidden, facts), to: SiteSections, as: :visible
  defdelegate public_tags(settings), to: SiteSettingsPolicy
  defdelegate tracking?(settings), to: SiteSettingsPolicy
  defdelegate section_keys(), to: SiteSections, as: :keys

  # ── Domains ─────────────────────────────────────────────────────────────

  defdelegate list_domains(context), to: BoxSiteStore
  defdelegate get_domain(context, id), to: BoxSiteStore
  defdelegate update_domain(context, id, changes), to: BoxSiteStore
  defdelegate make_primary(context, id), to: BoxSiteStore
  defdelegate delete_domain(context, id), to: BoxSiteStore
  defdelegate due_domains(context, now, limit), to: BoxSiteStore
  defdelegate site_by_host(host), to: BoxSiteStore
  defdelegate primary_host(organization_id), to: BoxSiteStore
  defdelegate domains_for_ops(status), to: BoxSiteStore
  defdelegate due_organizations(now), to: BoxSiteStore
  defdelegate domain_statuses(), to: DomainPolicy, as: :statuses
  defdelegate tls_allowed?(status), to: DomainPolicy
  defdelegate serving?(status), to: DomainPolicy
  defdelegate after_check(domain, facts, now), to: DomainPolicy

  @doc "Adds a custom host (up to #{DomainPolicy.max_domains()}); the first one is primary."
  def add_domain(context, host, user_id, now) do
    existing = BoxSiteStore.list_domains(context)

    with {:ok, host} <- Hostname.normalize(host, refused_suffixes()),
         :ok <- room_for_domain(existing) do
      token = DomainPolicy.new_token(:crypto.strong_rand_bytes(24))

      attrs =
        host
        |> DomainPolicy.new_domain(token, existing == [], now)
        |> Map.put(:created_by_id, user_id)

      BoxSiteStore.insert_domain(context, attrs)
    end
  end

  defp room_for_domain(existing) do
    if length(existing) >= DomainPolicy.max_domains(), do: {:error, :too_many_domains}, else: :ok
  end

  @doc "The DNS records the owner adds for a host."
  def dns_records(domain) do
    DomainPolicy.dns_records(domain, Hostname.apex?(domain.host), cname_target(), a_records())
  end

  @doc "What DNS says about a host now (TXT proof, routing)."
  def dns_facts(domain) do
    dns = dns()

    DomainPolicy.dns_facts(
      domain.verification_token,
      dns.lookup(DomainPolicy.challenge_name(domain.host), :txt),
      dns.lookup(domain.host, :cname),
      dns.lookup(domain.host, :a),
      cname_target(),
      a_records()
    )
  end

  # ── Forms ───────────────────────────────────────────────────────────────

  defdelegate form_kinds(), to: FormPolicy, as: :kinds
  defdelegate spam?(params), to: FormPolicy
  defdelegate validate_submission(kind, params, now), to: FormPolicy, as: :validate
  defdelegate intake(submission), to: FormPolicy
  defdelegate after_delivery(result, submission, now), to: FormPolicy
  defdelegate insert_submission(context, attrs), to: BoxSiteStore
  defdelegate claim_submissions(context, now, limit), to: BoxSiteStore
  defdelegate claim_conversions(context, now, limit), to: BoxSiteStore
  defdelegate finish_submission(context, id, changes), to: BoxSiteStore
  defdelegate submission_counts(context, since), to: BoxSiteStore

  @doc "Clears failed submissions older than the retention (ADR-353 §4)."
  def redact_failed(context, now) do
    cutoff = DateTime.add(now, -FormPolicy.failed_retention_days() * 86_400, :second)
    BoxSiteStore.redact_failed_before(context, cutoff, now)
  end

  defdelegate conversion_event(submission, source_url), to: ConversionEvent, as: :build
  defdelegate after_conversion(result, attempts, now), to: ConversionEvent, as: :after_send

  # ── Consent ─────────────────────────────────────────────────────────────

  defdelegate consent_categories(), to: ConsentPolicy, as: :categories
  defdelegate consent_validity_days(), to: ConsentPolicy, as: :validity_days
  defdelegate allowed_tags(tags, consent), to: ConsentPolicy
  defdelegate consent_counts(context, since), to: BoxSiteStore

  @doc "Records a visitor's choice in the log."
  def record_consent(context, params, banner_version, now) do
    with {:ok, attrs} <- ConsentPolicy.record(params, banner_version, now) do
      BoxSiteStore.insert_consent(context, attrs)
    end
  end

  @doc "What a visitor's latest choice still allows now."
  def effective_consent(context, visitor_id, banner_version, now) do
    context
    |> BoxSiteStore.latest_consent(visitor_id)
    |> ConsentPolicy.effective(banner_version, now)
  end

  @doc "Deletes log rows past their retention (ADR-354 §4)."
  def expire_consents(context, now),
    do: BoxSiteStore.delete_consents_before(context, ConsentPolicy.retention_cutoff(now))

  # ── Tenant data (ADR-117) ───────────────────────────────────────────────

  def tenant_data_policy, do: TenantDataPolicy.policy()

  def tenant_data_inventory(context),
    do: Palee.TenantData.TableStore.inventory(tenant_data_policy(), context)

  def export_tenant_data(context, mode \\ :full),
    do: Palee.TenantData.TableStore.export(tenant_data_policy(), context, mode)

  def purge_tenant_data(context),
    do: Palee.TenantData.TableStore.purge(tenant_data_policy(), context)
end

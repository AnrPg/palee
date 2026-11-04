defmodule Palee.Application.BoxSite.SiteAdmin do
  @moduledoc """
  ADR-352..354: the box's website for staff (`/admin/site`): its settings,
  custom domains and what the site brought in (counts only).
  """

  alias Palee.Application.{PublicURL, SignedToken}
  alias Palee.Application.BoxSite.{SiteDomainChecks, SiteIngresses, SiteTranslations}
  alias Palee.{BoxSite, ContentTranslations, Email, Organizations}
  alias Palee.Email.Domain.Address

  @status_salt "box-site-domain-status"
  @status_days 30

  @summary_days 30

  @doc "The settings, the section keys, the domains and the website's languages."
  def show(context) do
    settings = BoxSite.settings(context)

    {:ok,
     %{
       settings: present_settings(settings),
       section_keys: BoxSite.section_keys(),
       domains: domains(context),
       languages: languages(context, settings)
     }}
  end

  @doc "Saves an edit; answers the new settings and languages."
  def update(context, params) do
    params = stringify(params)

    with {:ok, params} <- SiteTranslations.clean_languages(context, params),
         {:ok, settings} <- BoxSite.update_settings(context, params, user_id(context)) do
      {:ok, %{settings: present_settings(settings), languages: languages(context, settings)}}
    end
  end

  # ADR-520: the box's own language, the languages it can add, and how far
  # each translation is.
  defp languages(context, settings) do
    source = SiteTranslations.source_language(context)

    %{
      source: source,
      available:
        Enum.reject(
          ContentTranslations.locales(),
          &(ContentTranslations.base_language(&1) == source)
        ),
      machine_available: ContentTranslations.machine_available?(),
      progress:
        context
        |> SiteTranslations.progress(settings)
        |> Enum.map(fn {locale, %{counts: counts, total: total}} ->
          %{locale: locale, counts: counts, total: total}
        end)
        |> Enum.sort_by(
          &Enum.find_index(settings.translation_locales, fn l -> l == &1.locale end)
        )
    }
  end

  @doc "The custom hosts with their DNS records."
  def domains(context), do: context |> BoxSite.list_domains() |> Enum.map(&present_domain/1)

  @doc "Adds a custom host and checks it at once."
  def add_domain(context, %{"host" => host}) when is_binary(host) do
    now = BoxSite.clock().now()

    with {:ok, domain} <- BoxSite.add_domain(context, host, user_id(context), now),
         {:ok, domain} <- SiteDomainChecks.check(context, domain, now) do
      {:ok, present_domain(domain)}
    end
  end

  def add_domain(_context, _params), do: {:error, :invalid_hostname}

  @doc "«Έλεγχος τώρα»: checks a host now."
  def check_domain(context, id) do
    with %{} = domain <- BoxSite.get_domain(context, id) || {:error, :site_domain_not_found},
         {:ok, domain} <- SiteDomainChecks.check(context, domain, BoxSite.clock().now()) do
      {:ok, present_domain(domain)}
    end
  end

  @doc "Makes a host the site's primary (canonical) one."
  def make_primary(context, id) do
    case BoxSite.make_primary(context, id) do
      {:ok, domain} -> {:ok, present_domain(domain)}
      {:error, :not_found} -> {:error, :site_domain_not_found}
      error -> error
    end
  end

  @doc "Removes a host (and, ADR-398, its Ingress); the site stays at its Palee address."
  def remove_domain(context, id) do
    with %{} = domain <- BoxSite.get_domain(context, id) || {:error, :site_domain_not_found},
         :ok <- BoxSite.delete_domain(context, id) do
      SiteIngresses.removed(context, domain, BoxSite.clock().now())
    else
      {:error, :not_found} -> {:error, :site_domain_not_found}
      error -> error
    end
  end

  @doc """
  ADR-388 «Στείλε τις οδηγίες»: emails the host's DNS records to whoever
  runs the domain, with a link (valid #{@status_days} days) to a page that
  shows whether they are found yet. A demo business sends nothing.
  """
  def send_instructions(%{organization_id: organization_id} = context, id, params) do
    params = stringify(params)

    with %{} = domain <- BoxSite.get_domain(context, id) || {:error, :site_domain_not_found},
         {:ok, to} <- address(Map.get(params, "email")),
         {:ok, _message} <- enqueue_instructions(organization_id, domain, to) do
      {:ok, %{sent_to: to}}
    end
  end

  defp address(value) do
    case Address.normalize(value) do
      {:ok, address} -> {:ok, address}
      _invalid -> {:error, {:invalid_fields, %{email: "invalid"}}}
    end
  end

  defp enqueue_instructions(organization_id, domain, to) do
    organization = Organizations.get_by_id(organization_id)
    settings = Organizations.get_organization_settings(organization_id)

    with %{} <- organization || {:error, :not_found},
         :ok <- Organizations.go_live(organization, :send_outside) do
      token = SignedToken.sign(@status_salt, %{"o" => organization_id, "d" => domain.id})

      Email.enqueue(
        :site_domain_instructions,
        to,
        %{
          box_name: (settings && settings.brand_name) || organization.name,
          host: domain.host,
          records: BoxSite.dns_records(domain),
          status_url: PublicURL.base_url() <> "/site-domain/" <> token
        },
        locale: (settings && settings.default_locale) || "el",
        organization_id: organization_id,
        idempotency_key:
          "site_domain_instructions:#{domain.id}:#{to}:#{Date.to_iso8601(Date.utc_today())}"
      )
    end
  end

  @doc "The page behind the emailed link: the host's state and records, or `{:error, :not_found}`."
  def domain_status(token) when is_binary(token) do
    with {:ok, %{"o" => organization_id, "d" => domain_id}} <-
           SignedToken.verify(@status_salt, token, max_age: @status_days * 86_400),
         context = %{organization_id: organization_id},
         %{} = domain <- BoxSite.get_domain(context, domain_id) do
      settings = Organizations.get_organization_settings(organization_id)
      organization = Organizations.get_by_id(organization_id)

      {:ok,
       %{
         host: domain.host,
         status: domain.status,
         last_error: domain.last_error,
         checked_at: domain.checked_at,
         box_name: (settings && settings.brand_name) || (organization && organization.name) || "",
         dns_records: BoxSite.dns_records(domain)
       }}
    else
      _invalid -> {:error, :not_found}
    end
  end

  def domain_status(_token), do: {:error, :not_found}

  @doc "Counts of the last #{@summary_days} days: form submissions and consent choices."
  def summary(context) do
    since = DateTime.add(BoxSite.clock().now(), -@summary_days * 86_400, :second)
    submissions = BoxSite.submission_counts(context, since)
    consents = BoxSite.consent_counts(context, since)

    {:ok,
     %{
       days: @summary_days,
       submissions: %{
         total: submissions |> Map.values() |> Enum.sum(),
         delivered: Map.get(submissions, "delivered", 0),
         waiting: Map.get(submissions, "pending", 0) + Map.get(submissions, "sending", 0),
         failed: Map.get(submissions, "failed", 0)
       },
       consents: %{
         accept_all: Map.get(consents, "accept_all", 0),
         reject_all: Map.get(consents, "reject_all", 0),
         custom: Map.get(consents, "custom", 0),
         withdraw: Map.get(consents, "withdraw", 0)
       }
     }}
  end

  @doc "Settings as the API shows them: never the Conversions API token."
  def present_settings(settings) do
    settings
    |> Map.take([
      :section_order,
      :hidden_sections,
      :public_schedule,
      :public_wod,
      :faq,
      :translation_locales,
      :visible_locales,
      :forms_enabled,
      :meta_pixel_id,
      :ga4_measurement_id,
      :gtm_container_id,
      :banner_version,
      :conversions_api_enabled,
      :has_conversions_api_token,
      :lock_version
    ])
  end

  @doc "A host as the API shows it, with the DNS records to add."
  def present_domain(domain) do
    domain
    |> Map.take([
      :id,
      :host,
      :primary,
      :status,
      :last_error,
      :checked_at,
      :next_check_at,
      :verified_at,
      :active_at,
      :certificate_status,
      :certificate_error
    ])
    |> Map.put(:dns_records, BoxSite.dns_records(domain))
  end

  defp user_id(context), do: Map.get(context, :user_id)

  defp stringify(params),
    do: Map.new(params || %{}, fn {key, value} -> {to_string(key), value} end)
end

defmodule Palee.Application.BoxSite.SiteAdmin do
  @moduledoc """
  ADR-352..354: the box's website for staff (`/admin/site`): its settings,
  custom domains and what the site brought in (counts only).
  """

  alias Palee.Application.BoxSite.SiteDomainChecks
  alias Palee.BoxSite

  @summary_days 30

  @doc "The settings, the section keys and the domains."
  def show(context) do
    {:ok,
     %{
       settings: present_settings(BoxSite.settings(context)),
       section_keys: BoxSite.section_keys(),
       domains: domains(context)
     }}
  end

  @doc "Saves an edit; answers the new settings."
  def update(context, params) do
    params = stringify(params)

    with {:ok, settings} <- BoxSite.update_settings(context, params, user_id(context)) do
      {:ok, %{settings: present_settings(settings)}}
    end
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

  @doc "Removes a host; the site stays at its Palee address."
  def remove_domain(context, id) do
    case BoxSite.delete_domain(context, id) do
      :ok -> :ok
      {:error, :not_found} -> {:error, :site_domain_not_found}
    end
  end

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
      :faq,
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
      :active_at
    ])
    |> Map.put(:dns_records, BoxSite.dns_records(domain))
  end

  defp user_id(context), do: Map.get(context, :user_id)

  defp stringify(params), do: Map.new(params || %{}, fn {key, value} -> {to_string(key), value} end)
end

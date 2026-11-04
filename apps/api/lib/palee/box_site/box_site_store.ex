defmodule Palee.BoxSite.BoxSiteStore do
  @moduledoc "Facade over the website adapter (ADR-352..354); tenant calls run in the caller's session."

  @behaviour Palee.BoxSite.Ports.BoxSiteStore

  alias Palee.Infrastructure.Tenancy.RepoContext

  defp adapter, do: Application.fetch_env!(:palee, :box_site_store)

  defp call(context, function, args),
    do: RepoContext.run(context, fn -> apply(adapter(), function, [context | args]) end)

  @impl true
  def get_settings(context), do: call(context, :get_settings, [])
  @impl true
  def conversions_api_token(context), do: call(context, :conversions_api_token, [])
  @impl true
  def save_settings(context, changes, lock_version),
    do: call(context, :save_settings, [changes, lock_version])

  @impl true
  def claim_template_notice(context, now), do: call(context, :claim_template_notice, [now])

  @impl true
  def list_domains(context), do: call(context, :list_domains, [])
  @impl true
  def get_domain(context, id), do: call(context, :get_domain, [id])
  @impl true
  def insert_domain(context, attrs), do: call(context, :insert_domain, [attrs])
  @impl true
  def update_domain(context, id, changes), do: call(context, :update_domain, [id, changes])
  @impl true
  def make_primary(context, id), do: call(context, :make_primary, [id])
  @impl true
  def delete_domain(context, id), do: call(context, :delete_domain, [id])
  @impl true
  def due_domains(context, now, limit), do: call(context, :due_domains, [now, limit])

  @impl true
  def queue_ingress_op(context, attrs), do: call(context, :queue_ingress_op, [attrs])
  @impl true
  def claim_ingress_ops(context, now, limit), do: call(context, :claim_ingress_ops, [now, limit])
  @impl true
  def finish_ingress_op(context, id, changes),
    do: call(context, :finish_ingress_op, [id, changes])

  @impl true
  def insert_submission(context, attrs), do: call(context, :insert_submission, [attrs])
  @impl true
  def claim_submissions(context, now, limit), do: call(context, :claim_submissions, [now, limit])
  @impl true
  def finish_submission(context, id, changes),
    do: call(context, :finish_submission, [id, changes])

  @impl true
  def claim_conversions(context, now, limit), do: call(context, :claim_conversions, [now, limit])
  @impl true
  def redact_failed_before(context, cutoff, now),
    do: call(context, :redact_failed_before, [cutoff, now])

  @impl true
  def submission_counts(context, since), do: call(context, :submission_counts, [since])

  @impl true
  def insert_consent(context, attrs), do: call(context, :insert_consent, [attrs])
  @impl true
  def latest_consent(context, visitor_id), do: call(context, :latest_consent, [visitor_id])
  @impl true
  def delete_consents_before(context, cutoff),
    do: call(context, :delete_consents_before, [cutoff])

  @impl true
  def consent_counts(context, since), do: call(context, :consent_counts, [since])

  # SECURITY DEFINER lookups: no tenant session.
  @impl true
  def site_by_host(host), do: adapter().site_by_host(host)
  @impl true
  def primary_host(organization_id), do: adapter().primary_host(organization_id)
  @impl true
  def domains_for_ops(status), do: adapter().domains_for_ops(status)
  @impl true
  def due_organizations(now), do: adapter().due_organizations(now)
  @impl true
  def ingress_hosts, do: adapter().ingress_hosts()
  @impl true
  def template_notices_due, do: adapter().template_notices_due()
end

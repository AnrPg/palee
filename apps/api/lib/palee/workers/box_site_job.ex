defmodule Palee.Workers.BoxSiteJob do
  @moduledoc """
  ADR-352/353: the website's background work. With an `organization_id` it
  serves that box (right after a form); without one (cron, every 5 minutes)
  it serves every box with due domain checks, outbox rows (forms and
  ADR-398 cluster calls) or retention, and sends the one-off notice of a
  site moved to «Αρένα» (ADR-530).
  """

  use Oban.Worker,
    queue: :box_site,
    max_attempts: 3,
    unique: [period: 30, keys: [:organization_id]]

  require Logger

  alias Palee.Application.BoxSite.{
    SiteDomainChecks,
    SiteIngresses,
    SiteOutbox,
    SiteTemplateNotice
  }

  alias Palee.BoxSite

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"organization_id" => organization_id}})
      when is_binary(organization_id) do
    serve(organization_id, BoxSite.clock().now())
  end

  def perform(_job) do
    now = BoxSite.clock().now()
    now |> BoxSite.due_organizations() |> Enum.each(&serve(&1, now))
    SiteTemplateNotice.run(now)
    :ok
  end

  defp serve(organization_id, now) do
    context = %{organization_id: organization_id}
    SiteDomainChecks.run_due(context, now)
    # ADR-398: the cluster calls (Ingress apply/delete) with their retries.
    SiteIngresses.run(context, now)
    SiteOutbox.run(context, now)
    :ok
  rescue
    error ->
      Logger.error("box site job failed for #{organization_id}: #{Exception.message(error)}")
      :ok
  end
end

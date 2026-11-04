defmodule Palee.Application.BoxSite.SiteTemplateNotice do
  @moduledoc """
  ADR-530: the migration moved every existing website to «Αρένα» and set
  `template_notice` (the banner on the settings page). Besides the banner,
  the box's staff who run the website (`manage_settings`: owners and
  admins) get one `site_template_changed` notification.

  `BoxSiteJob`'s cron calls `run/1`. Each box is claimed first (one
  `UPDATE ... WHERE template_notice_sent_at IS NULL`), so two workers or a
  retried job never notify twice; the notification's dedupe key guards each
  person too. A demo business is never listed (ADR-184), and a box that
  published or dismissed the notice first is not told any more.
  """

  require Logger

  alias Palee.{BoxSite, Notifications, Organizations}

  @doc "Notifies the staff of every box still waiting; answers how many boxes were told."
  def run(now) do
    BoxSite.template_notices_due()
    |> Enum.count(&notify(%{organization_id: &1}, now))
  end

  @doc "Tells one box's staff, once; `true` when this call told them."
  def notify(%{organization_id: organization_id} = context, now) do
    if BoxSite.claim_template_notice(context, now) do
      organization_id
      |> Organizations.list_user_ids_with_capability(:manage_settings)
      |> Enum.each(
        &Notifications.process_event("site_template_changed", %{
          user_id: &1,
          organization_id: organization_id
        })
      )

      true
    else
      false
    end
  rescue
    error ->
      Logger.warning("site template notice failed: #{Exception.message(error)}")
      false
  end
end

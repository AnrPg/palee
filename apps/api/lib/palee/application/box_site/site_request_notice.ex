defmodule Palee.Application.BoxSite.SiteRequestNotice do
  @moduledoc """
  ADR-388: who hears about a trial request or question from the website once
  it became a lead (ANR, 2026-11-02):

    * the lead's owner only, when the lead already has one (the same person
      wrote again);
    * otherwise every staff member whose roles handle «Ενδιαφερόμενοι»
      (`manage_leads`).

  A request never books a seat: the front desk confirms or calls back.
  """

  require Logger

  alias Palee.{Leads, Notifications, Organizations}

  @doc "Notifies the right staff about a delivered submission; never fails the delivery."
  def notify(%{organization_id: organization_id} = context, lead_id, submission) do
    recipients(context, lead_id)
    |> Enum.each(fn user_id ->
      Notifications.process_event("site_request", %{
        user_id: user_id,
        organization_id: organization_id,
        lead_id: lead_id,
        submission_id: submission.id,
        kind: submission.kind,
        person_name: Map.get(submission, :name)
      })
    end)
  rescue
    error -> Logger.warning("site request notice failed: #{Exception.message(error)}")
  end

  @doc "The staff to notify for a lead (see the module doc)."
  def recipients(%{organization_id: organization_id} = context, lead_id) do
    case Leads.get(context, lead_id) do
      %{owner_id: owner_id} when is_binary(owner_id) -> [owner_id]
      _no_owner -> Organizations.list_user_ids_with_capability(organization_id, :manage_leads)
    end
  end
end

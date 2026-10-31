defmodule Palee.Infrastructure.Leads.BoxSiteIntake do
  @moduledoc """
  ADR-345: the leads end of the box website's forms (CP-C4/C5, W4). W4's
  outbox calls `submit/2` (its port `Palee.BoxSite.Ports.LeadIntake`;
  the integration adds `@behaviour Palee.BoxSite.Ports.LeadIntake` here and
  sets `config :palee, :box_site_lead_intake, #{inspect(__MODULE__)}`).

  Idempotent on `submission_id`. Submitting the form is the person's
  contact consent for this request; `marketing_opt_in` is the separate
  marketing consent. `{:rejected, reason}` will never succeed (W4 stops
  retrying); `{:transient, reason}` is tried again.
  """

  @behaviour Palee.BoxSite.Ports.LeadIntake

  alias Palee.Application.Leads.CaptureLead

  @impl true
  def submit(%{organization_id: organization_id}, intake) when is_binary(organization_id) do
    consent = Map.get(intake, :consent) || %{}

    attrs = %{
      name: intake[:name],
      email: intake[:email],
      phone: intake[:phone],
      message: intake[:message],
      locale: intake[:locale],
      source: "website_form",
      source_ref: to_string(intake[:submission_id]),
      campaign: get_in(intake, [:attribution, :utm_campaign]),
      interests: if(intake[:kind] == "trial", do: ["trial"], else: []),
      consent: %{
        contact: true,
        marketing: intake[:marketing_opt_in] == true,
        given_at: intake[:submitted_at],
        text_version: consent[:text_version],
        text_hash: consent[:text_hash]
      },
      details: %{
        kind: intake[:kind],
        preferred_time: intake[:preferred_time],
        class_type_id: intake[:class_type_id],
        attribution: intake[:attribution],
        submitted_at: intake[:submitted_at] && DateTime.to_iso8601(intake[:submitted_at])
      }
    }

    case CaptureLead.call(%{organization_id: organization_id}, attrs) do
      {:ok, %{lead_id: lead_id}} -> {:ok, %{lead_id: lead_id}}
      {:error, {:invalid_fields, _errors}} -> {:error, {:rejected, :invalid_lead}}
      {:error, reason} -> {:error, {:transient, reason}}
    end
  end
end

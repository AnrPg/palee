defmodule Palee.Infrastructure.Leads.ProspectLeadSink do
  @moduledoc """
  ADR-344: the leads end of the prospect assistant (CP-C8, W8). Its port
  `Palee.ProspectAssistant.Ports.LeadSink` calls `capture/2` with the box's
  context and the lead it collected (the integration adds the
  `@behaviour` and sets `config :palee, :prospect_lead_sink`). Idempotent on
  the conversation (`source_ref`).
  """

  alias Palee.Application.Leads.CaptureLead

  def capture(%{organization_id: organization_id}, lead) when is_binary(organization_id) do
    attrs =
      lead
      |> Map.take([:name, :email, :phone, :message, :source_ref, :consent])
      |> Map.put(:source, "prospect_assistant")
      |> Map.put(:locale, lead[:language] || lead[:locale])

    case CaptureLead.call(%{organization_id: organization_id}, attrs) do
      {:ok, %{lead_id: lead_id}} -> {:ok, %{lead_id: lead_id}}
      {:error, reason} -> {:error, reason}
    end
  end
end

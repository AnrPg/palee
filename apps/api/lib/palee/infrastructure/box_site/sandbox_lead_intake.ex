defmodule Palee.Infrastructure.BoxSite.SandboxLeadIntake do
  @moduledoc """
  ADR-353: the lead intake for dev and test until the leads context's
  adapter is configured. It accepts every intake and answers a lead id
  derived from the submission id (so it is idempotent), keeping nothing.
  An intake named "reject me" is rejected and "retry me" fails transiently,
  so the outbox paths can be exercised.
  """

  @behaviour Palee.BoxSite.Ports.LeadIntake

  @impl true
  def submit(_context, %{name: "reject me"}), do: {:error, {:rejected, :invalid_lead}}
  def submit(_context, %{name: "retry me"}), do: {:error, {:transient, :sandbox_unavailable}}

  def submit(%{organization_id: _}, %{submission_id: id}) do
    <<lead::binary-size(16), _rest::binary>> = :crypto.hash(:sha256, "lead:" <> id)
    {:ok, %{lead_id: Ecto.UUID.load!(lead)}}
  end
end

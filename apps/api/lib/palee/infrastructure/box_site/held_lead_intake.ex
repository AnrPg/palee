defmodule Palee.Infrastructure.BoxSite.HeldLeadIntake do
  @moduledoc """
  ADR-353: the production intake until the leads context (CP-C1) is
  configured. Every intake is transient, so submissions wait in the outbox
  and are never lost; configuring the leads adapter delivers them.
  """

  @behaviour Palee.BoxSite.Ports.LeadIntake

  @impl true
  def submit(_context, _intake), do: {:error, {:transient, :leads_not_configured}}
end

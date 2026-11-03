defmodule Palee.Finance.DebtorContactStore do
  @moduledoc """
  ADR-450: the kept contacts of deleted debtors through the configured
  adapter. Callers run it inside the box's scope (`Finance.with_tenant_context/2`).
  """

  @behaviour Palee.Finance.Ports.DebtorContactStore

  defp adapter, do: Application.fetch_env!(:palee, :debtor_contact_store)

  @impl true
  def keep(attrs), do: adapter().keep(attrs)

  @impl true
  def for_users(user_ids), do: adapter().for_users(user_ids)

  @impl true
  def list, do: adapter().list()

  @impl true
  def release(membership_ids), do: adapter().release(membership_ids)
end

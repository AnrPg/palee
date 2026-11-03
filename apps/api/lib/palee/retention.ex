defmodule Palee.Retention do
  @moduledoc """
  The Retention bounded context (ADR-347): «Σε κίνδυνο», box members who
  may be about to leave, each with an explainable score and the reasons
  behind it, and what staff did about it. A member whose risk becomes high
  is announced (`:member_at_risk`) so the win-back recipe (ADR-346) can
  reach them when the box has it on.
  """

  alias Palee.Retention.{RiskStore, SignalReader}
  alias Palee.Retention.Domain.RiskScore

  @doc "The configured clock (`Retention.Ports.Clock`)."
  def clock,
    do: Application.fetch_env!(:palee, :retention_clock)

  def now, do: clock().now()

  defdelegate all(context), to: RiskStore
  defdelegate get(context, user_id), to: RiskStore
  defdelegate put(context, user_id, attrs), to: RiskStore
  defdelegate delete_except(context, user_ids), to: RiskStore
  defdelegate list(context, filters), to: RiskStore
  defdelegate level_counts(context), to: RiskStore
  defdelegate add_action(context, user_id, attrs), to: RiskStore
  defdelegate actions(context, user_id, limit), to: RiskStore
  defdelegate signals(context, today, now), to: SignalReader
  defdelegate score(signals), to: RiskScore
  defdelegate levels(), to: RiskScore
  defdelegate reason_codes(), to: RiskScore
  defdelegate actions(), to: RiskScore
  defdelegate action_kinds(), to: Palee.Retention.RiskAction, as: :kinds

  def tenant_data_policy, do: Palee.Retention.Domain.TenantDataPolicy.policy()

  def tenant_data_inventory(context),
    do: Palee.TenantData.TableStore.inventory(tenant_data_policy(), context)

  def export_tenant_data(context, mode \\ :full),
    do: Palee.TenantData.TableStore.export(tenant_data_policy(), context, mode)

  def purge_tenant_data(context),
    do: Palee.TenantData.TableStore.purge(tenant_data_policy(), context)
end

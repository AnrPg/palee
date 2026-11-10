defmodule Palee.Finance.MemberBenefitStore do
  @moduledoc "ADR-612: dispatches to the configured `Palee.Finance.Ports.MemberBenefitStore`."

  @behaviour Palee.Finance.Ports.MemberBenefitStore

  defp adapter, do: Application.fetch_env!(:palee, :member_benefit_store)

  @impl true
  def insert(params), do: adapter().insert(params)
  @impl true
  def by_idempotency_key(key), do: adapter().by_idempotency_key(key)
  @impl true
  def lock_grant(membership_id, id), do: adapter().lock_grant(membership_id, id)
  @impl true
  def list(membership_id), do: adapter().list(membership_id)
  @impl true
  def access(membership_id, today), do: adapter().access(membership_id, today)
  @impl true
  def transaction(fun), do: adapter().transaction(fun)
end

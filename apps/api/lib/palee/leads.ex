defmodule Palee.Leads do
  @moduledoc """
  The Leads bounded context (ADR-344, ADR-345): the box's «Ενδιαφερόμενοι».
  People who are not box members yet, where they came from, the stage they
  are at, who on the staff looks after them, what to do next, and how they
  became box members. The history stays after conversion.

  Every function runs in the box's scope (`%{organization_id: ...}`).
  Application services (`Palee.Application.Leads.*`) orchestrate; this
  module holds the pure rules and the store.
  """

  alias Palee.Leads.Domain.{IntakePolicy, LeadCsv, Pipeline}
  alias Palee.Leads.LeadStore

  # ADR-345: a lost lead that never became anyone's profile is deleted after
  # two years without a move.
  @stale_after_days 730

  def stale_after_days, do: @stale_after_days

  @doc "The configured clock (`Leads.Ports.Clock`)."
  def clock, do: Application.get_env(:palee, :leads_clock, Palee.Infrastructure.Leads.SystemClock)

  def now, do: clock().now()

  defdelegate transaction(context, fun), to: LeadStore
  defdelegate insert(context, attrs), to: LeadStore
  defdelegate update(context, lead, changes), to: LeadStore
  defdelegate get(context, id), to: LeadStore
  defdelegate get_for_update(context, id), to: LeadStore
  defdelegate get_by_source_ref(context, source, ref), to: LeadStore
  defdelegate find_by_email(context, email), to: LeadStore
  defdelegate open_for_person(context, user_id, email), to: LeadStore
  defdelegate list(context, filters), to: LeadStore
  defdelegate stage_counts(context), to: LeadStore
  defdelegate delete(context, id), to: LeadStore
  defdelegate add_event(context, attrs), to: LeadStore
  defdelegate events(context, lead_id), to: LeadStore
  defdelegate insert_task(context, attrs), to: LeadStore
  defdelegate get_task(context, id), to: LeadStore
  defdelegate complete_task(context, task, changes), to: LeadStore
  defdelegate tasks(context, lead_id), to: LeadStore
  defdelegate open_tasks(context, filters), to: LeadStore
  defdelegate next_tasks(context, lead_ids), to: LeadStore

  @doc "Deletes lost leads that did not move for `stale_after_days/0` (ADR-345)."
  def purge_stale(context, now),
    do: LeadStore.purge_stale(context, DateTime.add(now, -@stale_after_days, :day))

  defdelegate stages(), to: Pipeline
  defdelegate open_stages(), to: Pipeline
  defdelegate sources(), to: Pipeline
  defdelegate lost_reasons(), to: Pipeline
  defdelegate move(lead, to, now, opts), to: Pipeline
  defdelegate convert(lead, user_id, now), to: Pipeline
  defdelegate reenquiry(lead, now), to: Pipeline
  defdelegate normalize(attrs), to: IntakePolicy
  defdelegate consent(consent, source, now), to: IntakePolicy
  defdelegate spam_check(params, now), to: IntakePolicy
  defdelegate parse_csv(text), to: LeadCsv, as: :parse

  def tenant_data_policy, do: Palee.Leads.Domain.TenantDataPolicy.policy()

  def tenant_data_inventory(context),
    do: Palee.TenantData.TableStore.inventory(tenant_data_policy(), context)

  def export_tenant_data(context, mode \\ :full),
    do: Palee.TenantData.TableStore.export(tenant_data_policy(), context, mode)

  def purge_tenant_data(context),
    do: Palee.TenantData.TableStore.purge(tenant_data_policy(), context)
end

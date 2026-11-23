defmodule Palee.ActivityLog.Backfill do
  @moduledoc """
  ADR-760 (11A): the «Αρχείο ενεργειών» starts full. The changes staff made
  before the log existed are copied into it from the records the other
  contexts already keep: value overrides, freezes, benefits, package
  removals, members who left, cancelled classes and events, spaces taken
  out of use, reopened pay periods, credit notes, refunds, declined package
  requests, trials and season places, cancelled shop orders, revoked ranks
  and lost leads.

  Each copy keeps the original time, the actor, the person, the reason and
  the details where the source has them, with `source` `"backfill"` and a
  `source_ref` naming its source row, so copying twice adds nothing. A
  copied reason is never shown to the member (`reason_shared` false).

  One box at a time, in its own session (row-level security). A box whose
  backfill is at `@version` or later is skipped; raise `@version` when a
  source is added, and the next run copies what is missing.
  """

  alias Palee.Infrastructure.Tenancy.RepoContext

  require Logger

  @version 1
  @batch 500

  # Source → action key, or `kind` → action key where the source holds
  # several kinds of change (`ActivityLog.Domain.Actions`).
  @actions %{
    value_override_set: %{"status" => "member.status_set", "ends_on" => "package.end_set"},
    value_override_reset: %{"status" => "member.status_reset", "ends_on" => "package.end_reset"},
    freeze: "package.freeze",
    freeze_cancel: "package.freeze_cancel",
    benefit: %{"grant" => "benefit.give", "revoke" => "benefit.revoke"},
    package_removal: "package.remove",
    package_removal_undo: "package.removal_undo",
    member_leave: "member.leave_record",
    class_cancel: "class.state_change",
    event_cancel: "event.cancel",
    space_unavailable: "space.unavailable",
    pay_period_reopen: "pay_period.reopen",
    credit_note: "fiscal.credit_note",
    refund: "payment.refund",
    package_request_decline: "package_request.decline",
    trial_decline: "trial.decline",
    season_decline: "season.enrollment_decline",
    shop_order_cancel: "shop.order_cancel",
    rank_revoke: "rank.revoke",
    lead_lost: "lead.move"
  }

  def version, do: @version
  def sources, do: @actions |> Map.keys() |> Enum.sort()

  defp sources_store,
    do:
      Application.get_env(
        :palee,
        :activity_log_backfill_source_store,
        Palee.Infrastructure.ActivityLog.EctoBackfillSourceStore
      )

  defp log_store, do: Palee.ActivityLog.store_module()

  @doc """
  Copies one box's older records. `{:ok, inserted}` when it ran,
  `{:skipped, version}` when the box already has this version.
  """
  def run(organization_id) when is_binary(organization_id) do
    RepoContext.run(%{organization_id: organization_id}, fn ->
      case log_store().backfill_version() do
        done when is_integer(done) and done >= @version ->
          {:skipped, done}

        _missing_or_older ->
          inserted = Enum.reduce(sources(), 0, fn source, count -> count + copy(source) end)
          :ok = log_store().mark_backfilled(@version, inserted)

          Logger.info(
            "activity_log_backfill organization_id=#{organization_id} " <>
              "version=#{@version} entries=#{inserted}"
          )

          {:ok, inserted}
      end
    end)
  end

  defp copy(source, after_id \\ nil, count \\ 0) do
    facts = sources_store().read(source, after_id, @batch)

    inserted =
      facts
      |> Enum.flat_map(&entry(source, &1))
      |> log_store().insert_all_new()

    case facts do
      [] -> count + inserted
      _page when length(facts) < @batch -> count + inserted
      _full -> copy(source, List.last(facts).id, count + inserted)
    end
  end

  @doc false
  def entry(source, %{occurred_at: %DateTime{}} = fact) do
    case action(source, fact.kind) do
      nil ->
        []

      action ->
        [
          %{
            action: action,
            occurred_at: fact.occurred_at,
            actor_user_id: fact.actor_user_id,
            actor_roles: fact.actor_roles,
            person_user_id: fact.person_user_id,
            subject: fact.subject,
            subject_label: label(fact.subject_label),
            details: fact.details,
            reason: reason(fact.reason),
            reason_shared: false,
            source: "backfill",
            source_ref: fact.ref
          }
        ]
    end
  end

  def entry(_source, _fact), do: []

  defp action(source, kind) do
    case Map.fetch!(@actions, source) do
      by_kind when is_map(by_kind) -> Map.get(by_kind, kind)
      action -> action
    end
  end

  defp reason(text) when is_binary(text) do
    case String.trim(text) do
      "" -> nil
      trimmed -> String.slice(trimmed, 0, Palee.ActivityLog.Entry.max_reason())
    end
  end

  defp reason(_text), do: nil

  defp label(text) when is_binary(text), do: String.slice(text, 0, 300)
  defp label(_text), do: nil
end

defmodule Palee.Infrastructure.ActivityLog.EctoBackfillSourceStore do
  @moduledoc """
  ADR-760 (11A): reads the older records the «Αρχείο ενεργειών» is filled
  from, straight from the tables of the contexts that keep them. Every read
  runs in one box's session: row-level security admits only its rows, and
  each query also names the box (`organization_id = $1`).

  One source is one query, paged by the source row's id. Where a row holds
  two changes (an override set and later reset, a freeze and its
  cancellation) they are two sources, with a suffix on the second `ref`.

  Some sources did not keep everything: a cancelled class, event or freeze
  does not say who cancelled it, and a reopened pay period keeps only its
  reason, so its time is the period's last update.
  """

  @behaviour Palee.ActivityLog.Ports.BackfillSourceStore

  alias Palee.Infrastructure.Tenancy.RepoContext
  alias Palee.Repo

  @first_id "00000000-0000-0000-0000-000000000000"

  @null_roles "NULL::text[]"
  @no_subject "'{}'::jsonb"
  @no_details "'{}'::jsonb"

  @sources %{
    value_override_set: %{
      table: "finance_value_overrides",
      from: "finance_value_overrides s LEFT JOIN memberships m ON m.id = s.membership_id",
      at: "s.inserted_at",
      actor: "s.set_by_id",
      person: "m.user_id",
      kind: "s.field",
      reason: "s.reason",
      subject:
        "CASE WHEN s.subject_type = 'subscription' " <>
          "THEN jsonb_build_object('subscription_id', s.subject_id::text) ELSE '{}'::jsonb END",
      details:
        "jsonb_build_object('changes', jsonb_build_array(jsonb_build_object(" <>
          "'field', s.field, 'before', s.computed_value, 'after', s.value)))"
    },
    value_override_reset: %{
      table: "finance_value_overrides",
      suffix: ":reset",
      from: "finance_value_overrides s LEFT JOIN memberships m ON m.id = s.membership_id",
      where: "s.ended_at IS NOT NULL AND s.end_reason = 'reset'",
      at: "s.ended_at",
      actor: "s.ended_by_id",
      person: "m.user_id",
      kind: "s.field",
      subject:
        "CASE WHEN s.subject_type = 'subscription' " <>
          "THEN jsonb_build_object('subscription_id', s.subject_id::text) ELSE '{}'::jsonb END",
      details:
        "jsonb_build_object('changes', jsonb_build_array(jsonb_build_object(" <>
          "'field', s.field, 'before', s.value, 'after', s.computed_value)))"
    },
    freeze: %{
      table: "finance_subscription_freezes",
      from: :freezes,
      at: "s.inserted_at",
      actor: "s.admin_id",
      person: "m.user_id",
      label: "p.name",
      reason: "s.reason",
      subject:
        "jsonb_build_object('subscription_id', s.membership_package_subscription_id::text)",
      details:
        "jsonb_build_object('starts_on', s.starts_on, 'ends_on', s.ends_on, " <>
          "'extension_days', s.extension_days)"
    },
    freeze_cancel: %{
      table: "finance_subscription_freezes",
      suffix: ":cancel",
      from: :freezes,
      where: "s.cancelled_at IS NOT NULL",
      at: "s.cancelled_at",
      person: "m.user_id",
      label: "p.name",
      reason: "s.cancel_reason",
      subject:
        "jsonb_build_object('subscription_id', s.membership_package_subscription_id::text)",
      details: "jsonb_build_object('starts_on', s.starts_on, 'ends_on', s.ends_on)"
    },
    benefit: %{
      table: "finance_member_benefits",
      from: "finance_member_benefits s",
      at: "s.inserted_at",
      actor: "s.actor_id",
      roles: "s.actor_roles::text[]",
      person: "s.user_id",
      kind: "s.action",
      reason: "s.reason",
      subject: "jsonb_build_object('benefit_id', COALESCE(s.benefit_id, s.id)::text)",
      details:
        "jsonb_strip_nulls(jsonb_build_object('kind', s.kind, 'starts_on', s.starts_on, " <>
          "'ends_on', s.ends_on, 'amount_cents', s.amount_cents, " <>
          "'package_name', s.details->>'package_name'))"
    },
    package_removal: %{
      table: "finance_package_removals",
      from: "finance_package_removals s",
      at: "s.inserted_at",
      actor: "s.actor_id",
      roles: "s.actor_roles::text[]",
      person: "s.user_id",
      label: "s.package_name",
      reason: "s.reason",
      subject: "jsonb_build_object('subscription_id', s.subscription_id::text)",
      details:
        "jsonb_strip_nulls(jsonb_build_object('removed_on', s.removed_on, " <>
          "'previous_status', s.previous_status))"
    },
    package_removal_undo: %{
      table: "finance_package_removals",
      suffix: ":undo",
      from: "finance_package_removals s",
      where: "s.undone_at IS NOT NULL",
      at: "s.undone_at",
      actor: "s.undone_by_id",
      person: "s.user_id",
      label: "s.package_name",
      subject: "jsonb_build_object('subscription_id', s.subscription_id::text)"
    },
    member_leave: %{
      table: "memberships",
      from: "memberships s",
      where: "s.left_at IS NOT NULL",
      at: "s.left_at",
      # The member left by themselves; staff who marked them are not kept.
      actor: "CASE WHEN s.left_by = 'member' THEN s.user_id END",
      roles: "CASE WHEN s.left_by = 'member' THEN ARRAY['member'] END",
      person: "s.user_id",
      reason: "s.leave_reason",
      details: "jsonb_build_object('left_by', s.left_by, 'leaving_on', s.leaving_on)"
    },
    class_cancel: %{
      table: "scheduled_classes",
      from: "scheduled_classes s",
      where: "s.cancelled_at IS NOT NULL",
      at: "s.cancelled_at",
      label: "s.name",
      reason: "s.cancel_reason",
      subject: "jsonb_build_object('id', s.id::text)",
      details:
        "jsonb_build_object('state', 'cancel', 'scheduled_at', " <>
          "to_char(s.scheduled_at, 'YYYY-MM-DD\"T\"HH24:MI:SS\"Z\"'))"
    },
    event_cancel: %{
      table: "community_events",
      from: "community_events s",
      where: "s.cancelled_at IS NOT NULL",
      at: "s.cancelled_at",
      label: "s.title",
      reason: "s.cancel_reason",
      subject: "jsonb_build_object('id', s.id::text)",
      details:
        "jsonb_build_object('starts_at', to_char(s.starts_at, 'YYYY-MM-DD\"T\"HH24:MI:SS\"Z\"'))"
    },
    space_unavailable: %{
      table: "space_unavailabilities",
      from: "space_unavailabilities s LEFT JOIN spaces sp ON sp.id = s.space_id",
      at: "s.inserted_at",
      actor: "s.created_by_id",
      label: "sp.name",
      reason: "s.reason",
      subject: "jsonb_build_object('id', s.space_id::text)",
      details:
        "jsonb_build_object(" <>
          "'starts_at', to_char(s.starts_at, 'YYYY-MM-DD\"T\"HH24:MI:SS\"Z\"'), " <>
          "'ends_at', to_char(s.ends_at, 'YYYY-MM-DD\"T\"HH24:MI:SS\"Z\"'))"
    },
    pay_period_reopen: %{
      table: "coach_pay_periods",
      from: "coach_pay_periods s",
      where: "s.reopen_reason IS NOT NULL",
      at: "s.updated_at",
      reason: "s.reopen_reason",
      subject: "jsonb_build_object('id', s.id::text)",
      details: "jsonb_build_object('starts_on', s.starts_on, 'ends_on', s.ends_on)"
    },
    credit_note: %{
      table: "fiscal_documents",
      from: "fiscal_documents s",
      where: "s.kind = 'credit_note'",
      at: "s.issued_at",
      actor: "s.created_by_id",
      label: "s.number",
      subject: "jsonb_build_object('id', s.id::text)",
      details:
        "jsonb_strip_nulls(jsonb_build_object('credit_reason', s.credit_reason, " <>
          "'gross_cents', s.gross_cents, 'currency', s.currency, " <>
          "'corrects_document_id', s.corrects_document_id::text))"
    },
    refund: %{
      table: "finance_payment_reversals",
      from: "finance_payment_reversals s",
      where: "s.reversal_type = 'refund' AND s.deleted_at IS NULL",
      at: "COALESCE(s.occurred_at, s.inserted_at)",
      actor: "s.created_by_id",
      person: "s.user_id",
      reason: "s.reason",
      subject:
        "jsonb_strip_nulls(jsonb_build_object('payment_id', s.membership_payment_id::text))",
      details:
        "jsonb_strip_nulls(jsonb_build_object('amount_cents', s.amount_cents, " <>
          "'currency', s.currency, 'source_type', s.source_type))"
    },
    package_request_decline: %{
      table: "finance_package_requests",
      from: "finance_package_requests s",
      where: "s.status = 'declined'",
      at: "COALESCE(s.closed_at, s.updated_at)",
      actor: "s.closed_by_id",
      person: "s.user_id",
      label: "s.package_name_snapshot",
      reason: "s.decline_reason",
      subject: "jsonb_build_object('id', s.id::text)"
    },
    trial_decline: %{
      table: "scheduling_trial_requests",
      from: "scheduling_trial_requests s",
      where: "s.status = 'declined'",
      at: "COALESCE(s.decided_at, s.updated_at)",
      actor: "s.decided_by_id",
      person: "s.user_id",
      label: "s.class_name",
      reason: "s.decline_reason",
      subject: "jsonb_build_object('id', s.id::text)"
    },
    season_decline: %{
      table: "season_enrollments",
      from: "season_enrollments s LEFT JOIN season_offerings o ON o.id = s.season_offering_id",
      where: "s.status = 'declined'",
      at: "COALESCE(s.decided_at, s.updated_at)",
      actor: "s.decided_by_id",
      person: "s.user_id",
      label: "o.title",
      reason: "s.decline_reason",
      subject: "jsonb_build_object('id', s.season_offering_id::text)"
    },
    shop_order_cancel: %{
      table: "shop_orders",
      from: "shop_orders s",
      where: "s.status = 'cancelled'",
      at: "COALESCE(s.cancelled_at, s.updated_at)",
      actor: "s.handled_by_id",
      person: "s.user_id",
      label: "'#' || s.number::text",
      reason: "s.cancel_reason",
      subject: "jsonb_build_object('id', s.id::text)",
      details: "jsonb_build_object('total_cents', s.total_cents, 'currency', s.currency)"
    },
    rank_revoke: %{
      table: "rank_awards",
      from: "rank_awards s LEFT JOIN ranks r ON r.id = s.rank_id",
      where: "s.revoked_at IS NOT NULL",
      at: "s.revoked_at",
      actor: "s.revoked_by_id",
      person: "s.user_id",
      label: "r.name",
      reason: "s.revoke_reason",
      subject: "jsonb_build_object('id', s.id::text)",
      details: "jsonb_build_object('awarded_on', s.awarded_on)"
    },
    lead_lost: %{
      table: "lead_events",
      from: "lead_events s JOIN leads l ON l.id = s.lead_id",
      where: "s.kind = 'stage_changed' AND s.data->>'to' = 'lost'",
      at: "s.at",
      actor: "s.actor_id",
      person: "l.user_id",
      label: "l.name",
      reason: "s.data->>'lost_reason'",
      subject: "jsonb_build_object('id', s.lead_id::text)",
      details: "jsonb_build_object('from', s.data->>'from', 'to', 'lost')"
    }
  }

  @froms %{
    freezes:
      "finance_subscription_freezes s " <>
        "LEFT JOIN memberships m ON m.id = s.membership_id " <>
        "LEFT JOIN membership_package_subscriptions ps " <>
        "ON ps.id = s.membership_package_subscription_id " <>
        "LEFT JOIN membership_packages p ON p.id = ps.membership_package_id"
  }

  @doc "The sources this store can read."
  def sources, do: @sources |> Map.keys() |> Enum.sort()

  @impl true
  def read(source, after_id, limit) when is_atom(source) and is_integer(limit) and limit > 0 do
    spec = Map.fetch!(@sources, source)

    case RepoContext.current_setting("app.organization_id") do
      organization_id when is_binary(organization_id) ->
        %{rows: rows} =
          Repo.query!(sql(spec), [
            Ecto.UUID.dump!(organization_id),
            Ecto.UUID.dump!(after_id || @first_id),
            limit
          ])

        Enum.map(rows, &fact(spec, &1))

      _none ->
        []
    end
  end

  defp sql(spec) do
    from = Map.get(@froms, spec.from, spec.from)
    where = Map.get(spec, :where, "TRUE")

    """
    SELECT s.id::text, (#{spec.at})::timestamp, (#{Map.get(spec, :actor, "NULL")})::text,
           (#{Map.get(spec, :person, "NULL")})::text, (#{Map.get(spec, :kind, "NULL")})::text,
           (#{Map.get(spec, :label, "NULL")})::text, (#{Map.get(spec, :reason, "NULL")})::text,
           #{Map.get(spec, :roles, @null_roles)}, #{Map.get(spec, :subject, @no_subject)},
           #{Map.get(spec, :details, @no_details)}
      FROM #{from}
     WHERE s.organization_id = $1 AND s.id > $2 AND (#{where})
     ORDER BY s.id
     LIMIT $3
    """
  end

  defp fact(spec, [id, at, actor, person, kind, label, reason, roles, subject, details]) do
    %{
      ref: spec.table <> ":" <> id <> Map.get(spec, :suffix, ""),
      id: id,
      occurred_at: utc(at),
      kind: kind,
      actor_user_id: actor,
      actor_roles: roles || [],
      person_user_id: person,
      subject: subject || %{},
      subject_label: label,
      reason: reason,
      details: details || %{}
    }
  end

  defp utc(%NaiveDateTime{} = at), do: DateTime.from_naive!(at, "Etc/UTC")
  defp utc(nil), do: nil
end

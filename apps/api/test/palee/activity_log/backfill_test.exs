defmodule Palee.ActivityLog.BackfillTest do
  use Palee.DataCase, async: false
  use Oban.Testing, repo: Palee.Repo

  import Palee.AnalyticsHelpers, only: [organization_fixture: 0]

  alias Palee.ActivityLog.Backfill
  alias Palee.ActivityLog.Domain.Actions
  alias Palee.Infrastructure.ActivityLog.EctoBackfillSourceStore
  alias Palee.Infrastructure.Tenancy.RepoContext
  alias Palee.TestFixtures
  alias Palee.Workers.ActivityLogBackfillJob

  defp sql!(organization_id, statement, params) do
    RepoContext.run(%{organization_id: organization_id}, fn ->
      Repo.query!(statement, params)
    end)
  end

  defp dump(id), do: Ecto.UUID.dump!(id)

  defp entries(organization_id) do
    RepoContext.run(%{organization_id: organization_id}, fn ->
      Repo.query!(
        "SELECT action, source, source_ref, occurred_at, actor_user_id::text, " <>
          "person_user_id::text, reason, reason_shared, subject_label, details " <>
          "FROM activity_log_entries WHERE organization_id = $1 ORDER BY source_ref",
        [dump(organization_id)]
      ).rows
      |> Enum.map(fn [action, source, ref, at, actor, person, reason, shared, label, details] ->
        %{
          action: action,
          source: source,
          source_ref: ref,
          occurred_at: at,
          actor: actor,
          person: person,
          reason: reason,
          reason_shared: shared,
          label: label,
          details: details
        }
      end)
    end)
  end

  defp backfill_row(organization_id) do
    RepoContext.run(%{organization_id: organization_id}, fn ->
      Repo.query!(
        "SELECT version, entries FROM activity_log_backfills WHERE organization_id = $1",
        [dump(organization_id)]
      ).rows
    end)
  end

  # The test role is not held by row-level security, so the reads name the box.

  # A box with a space taken out of use, a declined trial, a reopened pay
  # period and a lost lead.
  defp seed(organization_id, staff, member) do
    space_id = Ecto.UUID.generate()
    unavailability_id = Ecto.UUID.generate()
    trial_id = Ecto.UUID.generate()
    period_id = Ecto.UUID.generate()
    lead_id = Ecto.UUID.generate()
    event_id = Ecto.UUID.generate()

    sql!(
      organization_id,
      "INSERT INTO spaces (id, organization_id, name, inserted_at, updated_at) " <>
        "VALUES ($1, $2, 'Αίθουσα Α', now(), now())",
      [dump(space_id), dump(organization_id)]
    )

    sql!(
      organization_id,
      "INSERT INTO space_unavailabilities (id, organization_id, space_id, starts_at, ends_at, " <>
        "reason, created_by_id, inserted_at, updated_at) VALUES ($1, $2, $3, " <>
        "'2026-03-01 08:00', '2026-03-02 08:00', 'Βάψιμο', $4, '2026-02-20 10:00', now())",
      [dump(unavailability_id), dump(organization_id), dump(space_id), dump(staff.id)]
    )

    sql!(
      organization_id,
      "INSERT INTO scheduling_trial_requests (id, organization_id, user_id, status, " <>
        "class_starts_at, class_name, decided_at, decided_by_id, decline_reason, " <>
        "inserted_at, updated_at) VALUES ($1, $2, $3, 'declined', '2026-04-01 18:00', " <>
        "'WOD', '2026-03-30 12:00', $4, 'Γεμάτο', now(), now())",
      [dump(trial_id), dump(organization_id), dump(member.id), dump(staff.id)]
    )

    sql!(
      organization_id,
      "INSERT INTO coach_pay_periods (id, organization_id, starts_on, ends_on, status, " <>
        "currency, reopen_reason, inserted_at, updated_at) VALUES ($1, $2, '2026-01-01', " <>
        "'2026-01-31', 'draft', 'EUR', 'Λάθος ώρες', now(), '2026-02-05 09:00')",
      [dump(period_id), dump(organization_id)]
    )

    sql!(
      organization_id,
      "INSERT INTO leads (id, organization_id, name, email, stage, source, lost_reason, " <>
        "stage_changed_at, inserted_at, updated_at) VALUES ($1, $2, 'Νίκος', " <>
        "'nikos@example.com', 'lost', 'website', 'price', now(), now(), now())",
      [dump(lead_id), dump(organization_id)]
    )

    sql!(
      organization_id,
      "INSERT INTO lead_events (id, organization_id, lead_id, kind, data, actor_id, at, " <>
        "inserted_at) VALUES ($1, $2, $3, 'stage_changed', $4, $5, '2026-01-10 11:00', now())",
      [
        dump(event_id),
        dump(organization_id),
        dump(lead_id),
        %{"from" => "trial", "to" => "lost", "lost_reason" => "price"},
        dump(staff.id)
      ]
    )

    %{unavailability: unavailability_id, trial: trial_id, period: period_id, lead_event: event_id}
  end

  setup do
    {organization, owner, _context} = organization_fixture()
    member = TestFixtures.user_fixture()
    ids = seed(organization.id, owner, member)
    %{organization: organization, owner: owner, member: member, ids: ids}
  end

  test "every source maps to known action keys and the store reads them all" do
    assert Backfill.sources() == EctoBackfillSourceStore.sources()

    for key <-
          ~w(member.status_set member.status_reset package.end_set package.end_reset
             package.freeze package.freeze_cancel benefit.give benefit.revoke package.remove
             package.removal_undo member.leave_record class.state_change event.cancel
             space.unavailable pay_period.reopen fiscal.credit_note payment.refund
             package_request.decline trial.decline season.enrollment_decline
             shop.order_cancel rank.revoke lead.move) do
      assert Actions.known?(key), key
    end
  end

  test "a source with several kinds picks the key by kind" do
    fact = %{
      ref: "finance_member_benefits:x",
      id: Ecto.UUID.generate(),
      occurred_at: ~U[2026-01-01 10:00:00Z],
      kind: "revoke",
      actor_user_id: nil,
      actor_roles: [],
      person_user_id: nil,
      subject: %{},
      subject_label: nil,
      reason: "  ",
      details: %{}
    }

    assert [%{action: "benefit.revoke", reason: nil, reason_shared: false, source: "backfill"}] =
             Backfill.entry(:benefit, fact)

    assert [%{action: "package.end_set"}] =
             Backfill.entry(:value_override_set, %{fact | kind: "ends_on"})

    assert [] = Backfill.entry(:benefit, %{fact | kind: "other"})
    assert [] = Backfill.entry(:benefit, %{fact | occurred_at: nil})
  end

  test "every source query runs in a box's session", %{organization: organization} do
    RepoContext.run(%{organization_id: organization.id}, fn ->
      for source <- Backfill.sources() do
        assert is_list(EctoBackfillSourceStore.read(source, nil, 10))
      end
    end)
  end

  test "copies a box's older records once, with their time, actor, person and reason",
       %{organization: organization, owner: owner, member: member, ids: ids} do
    assert {:ok, 4} = Backfill.run(organization.id)

    rows = entries(organization.id)
    assert length(rows) == 4
    assert Enum.all?(rows, &(&1.source == "backfill" and &1.reason_shared == false))

    by_ref = Map.new(rows, &{&1.source_ref, &1})

    space = by_ref["space_unavailabilities:#{ids.unavailability}"]
    assert space.action == "space.unavailable"
    assert space.actor == owner.id
    assert space.reason == "Βάψιμο"
    assert space.label == "Αίθουσα Α"
    assert space.occurred_at == ~N[2026-02-20 10:00:00.000000]
    assert space.details["starts_at"] == "2026-03-01T08:00:00Z"

    trial = by_ref["scheduling_trial_requests:#{ids.trial}"]
    assert trial.action == "trial.decline"
    assert trial.person == member.id
    assert trial.actor == owner.id
    assert trial.reason == "Γεμάτο"
    assert trial.occurred_at == ~N[2026-03-30 12:00:00.000000]

    period = by_ref["coach_pay_periods:#{ids.period}"]
    assert period.action == "pay_period.reopen"
    assert period.actor == nil
    assert period.reason == "Λάθος ώρες"

    lead = by_ref["lead_events:#{ids.lead_event}"]
    assert lead.action == "lead.move"
    assert lead.reason == "price"
    assert lead.label == "Νίκος"
    assert lead.details == %{"from" => "trial", "to" => "lost"}

    assert [[1, 4]] = backfill_row(organization.id)
  end

  test "a second run at the same version is skipped; an older version copies only what is new",
       %{organization: organization} do
    assert {:ok, 4} = Backfill.run(organization.id)
    assert {:skipped, 1} = Backfill.run(organization.id)

    # As if the box had an older backfill: everything is read again and
    # nothing is copied twice.
    RepoContext.run(%{organization_id: organization.id}, fn ->
      Palee.ActivityLog.store_module().mark_backfilled(0, 4)
    end)

    assert {:ok, 0} = Backfill.run(organization.id)
    assert length(entries(organization.id)) == 4
    assert [[1, 0]] = backfill_row(organization.id)
  end

  test "copies each box only from its own records", %{organization: organization} do
    {other, other_owner, _context} = organization_fixture()
    other_member = TestFixtures.user_fixture()
    seed(other.id, other_owner, other_member)

    assert {:ok, 4} = Backfill.run(organization.id)
    assert entries(other.id) == []
    assert backfill_row(other.id) == []

    assert {:ok, 4} = Backfill.run(other.id)

    refs = fn id -> id |> entries() |> MapSet.new(& &1.source_ref) end
    assert MapSet.disjoint?(refs.(organization.id), refs.(other.id))
  end

  test "pages through more rows than one batch", %{organization: organization, owner: owner} do
    space_id = Ecto.UUID.generate()

    sql!(
      organization.id,
      "INSERT INTO spaces (id, organization_id, name, inserted_at, updated_at) " <>
        "VALUES ($1, $2, 'Β', now(), now())",
      [dump(space_id), dump(organization.id)]
    )

    sql!(
      organization.id,
      "INSERT INTO space_unavailabilities (id, organization_id, space_id, starts_at, ends_at, " <>
        "created_by_id, inserted_at, updated_at) SELECT gen_random_uuid(), $1, $2, now(), " <>
        "now() + interval '1 hour', $3, now(), now() FROM generate_series(1, 520)",
      [dump(organization.id), dump(space_id), dump(owner.id)]
    )

    assert {:ok, 524} = Backfill.run(organization.id)
  end

  test "the hourly job backfills every active box", %{organization: organization} do
    assert :ok = perform_job(ActivityLogBackfillJob, %{})
    assert length(entries(organization.id)) == 4
    assert [[1, 4]] = backfill_row(organization.id)

    assert :ok = perform_job(ActivityLogBackfillJob, %{})
    assert length(entries(organization.id)) == 4
  end
end

defmodule Palee.Workers.ActivityLogDigestJobTest do
  # ADR-760 (ANR 12B): the owners hear each morning what sensitive actions
  # the staff did the box's day before: only owners, only on days with any,
  # once a day, by the box's own clock.
  use Palee.DataCase, async: false

  import Ecto.Query
  import Palee.TestFixtures

  alias Palee.{ActivityLog, Email, Organizations, Repo}
  alias Palee.ActivityLog.Domain.OwnerDigest
  alias Palee.Notifications.Notification
  alias Palee.TimeZones.ZonedTime
  alias Palee.Workers.ActivityLogDigestJob

  setup do
    owner = admin_fixture(%{nickname: "digest_owner_#{System.unique_integer([:positive])}"})
    co_owner = user_fixture()
    admin = user_fixture()
    desk = user_fixture()

    {:ok, organization} =
      Organizations.create_organization(%{
        name: "Digest Box #{System.unique_integer([:positive])}"
      })

    add_member(organization, owner, :owner)
    add_member(organization, co_owner, :owner)
    add_member(organization, admin, :admin)
    add_member(organization, desk, :front_desk)
    activate_business!(organization.id)

    zone = Organizations.organization_timezone(organization.id)
    today = ZonedTime.local_date(DateTime.utc_now(), zone)

    %{
      owner: owner,
      co_owner: co_owner,
      admin: admin,
      desk: desk,
      organization: organization,
      context: %{organization_id: organization.id},
      zone: zone,
      today: today,
      yesterday: Date.add(today, -1)
    }
  end

  defp add_member(organization, user, role) do
    {:ok, _membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: user.id,
        role: role,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    user
  end

  defp at(ctx, date, time), do: ZonedTime.to_utc(date, time, ctx.zone)

  defp record(ctx, action, occurred_at) do
    {:ok, _entry} =
      ActivityLog.record(Map.put(ctx.context, :user_id, ctx.admin.id), %{
        action: action,
        occurred_at: occurred_at,
        actor_roles: ["admin"]
      })
  end

  defp digests(ctx) do
    Repo.all(
      from n in Notification,
        where: n.organization_id == ^ctx.organization.id and n.type == :activity_log_digest
    )
  end

  test "sends yesterday's counts per kind to the owners only, with the filtered link", ctx do
    record(ctx, "fiscal.credit_note", at(ctx, ctx.yesterday, ~T[10:00:00]))
    record(ctx, "fiscal.credit_note", at(ctx, ctx.yesterday, ~T[18:30:00]))
    record(ctx, "benefit.give", at(ctx, ctx.yesterday, ~T[12:00:00]))
    # Not sensitive: not in the summary.
    record(ctx, "payment.record", at(ctx, ctx.yesterday, ~T[11:00:00]))

    assert {:ok, 2} = ActivityLogDigestJob.run(ctx.context, at(ctx, ctx.today, ~T[07:05:00]))

    notifications = digests(ctx)

    assert Enum.sort(Enum.map(notifications, & &1.user_id)) ==
             Enum.sort([ctx.owner.id, ctx.co_owner.id])

    date = Date.to_iso8601(ctx.yesterday)

    for %{payload: payload} <- notifications do
      assert payload["total"] == 3
      assert payload["date"] == date

      assert payload["counts"] == [
               %{"action" => "fiscal.credit_note", "count" => 2},
               %{"action" => "benefit.give", "count" => 1}
             ]

      assert payload["url"] == "/admin/activity-log?sensitive=1&from=#{date}&to=#{date}"
      assert is_binary(payload["title"]) and payload["title"] =~ "3"
      refute payload["title"] =~ ~r/milos/i
    end

    emails = Email.list_by_idempotency_prefix(OwnerDigest.key(ctx.organization.id, ctx.yesterday))
    assert length(emails) == 2
    assert Enum.all?(emails, &(&1.kind == "activity_log_digest"))
  end

  test "waits for the box's morning, then sends once that day", ctx do
    record(ctx, "package.end_set", at(ctx, ctx.yesterday, ~T[09:00:00]))

    assert :not_yet = ActivityLogDigestJob.run(ctx.context, at(ctx, ctx.today, ~T[06:30:00]))
    assert digests(ctx) == []

    assert {:ok, 2} = ActivityLogDigestJob.run(ctx.context, at(ctx, ctx.today, ~T[07:00:00]))
    assert {:ok, 2} = ActivityLogDigestJob.run(ctx.context, at(ctx, ctx.today, ~T[08:00:00]))
    assert {:ok, 2} = ActivityLogDigestJob.run(ctx.context, at(ctx, ctx.today, ~T[23:00:00]))

    assert length(digests(ctx)) == 2

    assert length(
             Email.list_by_idempotency_prefix(OwnerDigest.key(ctx.organization.id, ctx.yesterday))
           ) == 2
  end

  test "a day without sensitive actions sends nothing", ctx do
    record(ctx, "payment.record", at(ctx, ctx.yesterday, ~T[10:00:00]))
    # Today's sensitive action belongs to tomorrow's summary.
    record(ctx, "payment.refund", at(ctx, ctx.today, ~T[00:30:00]))

    assert :nothing = ActivityLogDigestJob.run(ctx.context, at(ctx, ctx.today, ~T[09:00:00]))
    assert digests(ctx) == []

    assert Email.list_by_idempotency_prefix(OwnerDigest.key(ctx.organization.id, ctx.yesterday)) ==
             []
  end

  test "counts the box's day, not the UTC one", ctx do
    before_day = Date.add(ctx.yesterday, -1)

    # Just inside the box's yesterday at both ends, and just outside it.
    record(ctx, "payment.refund", at(ctx, ctx.yesterday, ~T[00:00:00]))
    record(ctx, "payment.refund", at(ctx, ctx.yesterday, ~T[23:59:00]))
    record(ctx, "payment.refund", at(ctx, before_day, ~T[23:59:00]))
    record(ctx, "payment.refund", at(ctx, ctx.today, ~T[00:00:00]))

    assert {:ok, 2} = ActivityLogDigestJob.run(ctx.context, at(ctx, ctx.today, ~T[07:30:00]))

    assert [%{payload: %{"total" => 2}}, %{payload: %{"total" => 2}}] = digests(ctx)
  end

  test "each box reads only its own rows", ctx do
    {:ok, other} =
      Organizations.create_organization(%{
        name: "Other Box #{System.unique_integer([:positive])}"
      })

    other_owner = add_member(other, user_fixture(), :owner)
    activate_business!(other.id)

    record(ctx, "invoice.void", at(ctx, ctx.yesterday, ~T[10:00:00]))

    assert :nothing =
             ActivityLogDigestJob.run(
               %{organization_id: other.id},
               at(ctx, ctx.today, ~T[08:00:00])
             )

    assert Repo.all(
             from n in Notification,
               where: n.user_id == ^other_owner.id and n.type == :activity_log_digest
           ) == []
  end

  test "the hourly job runs every active box", ctx do
    record(ctx, "credit.create", at(ctx, ctx.yesterday, ~T[10:00:00]))

    assert :ok = ActivityLogDigestJob.perform(%Oban.Job{})

    # Whether it sent depends on the hour now on the box's clock.
    case OwnerDigest.due_day(DateTime.utc_now(), ctx.zone) do
      {:ok, _day} -> assert length(digests(ctx)) == 2
      :not_yet -> assert digests(ctx) == []
    end
  end
end

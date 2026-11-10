defmodule Palee.Repo.Migrations.NotificationGroupKey do
  @moduledoc """
  ADR-600: similar notifications stack in the bell. Each notification gets
  `group_key` when it is written (`Domain.NotificationGrouping`); rows with
  the same key form one stack. The stacked inbox partitions the live inbox by
  it, and a stack's read, delete and restore filter by it, so the live rows
  get a partial index on `(user_id, group_key)`.

  The rows written before this get the key the rules give them, with the
  day on the box's clock (the recipient's without a box), exactly as the app
  writes it from now on, so an older notification of today joins the stack of
  the new ones. Nothing else of a row changes.
  """

  use Ecto.Migration

  @conversation_rules [
    {"chat_message", "thread_id"},
    {"coaching_message", "thread_id"},
    {"box_message", "thread_id"},
    {"box_inbox_message", "thread_id"},
    {"person_message", "conversation_id"},
    {"message_request", "conversation_id"},
    {"buddy_message", "link_id"},
    {"partner_message", "match_id"},
    {"support_reply", "request_id"},
    {"community_event_message", "event_id"}
  ]

  @personal_day_types ~w(follow_requested new_follower follow_accepted)
  @subject_day_types ~w(workout_changed workout_note workout_moved)
  @never_types ~w(password_reset_requested password_reset_completed)

  def up do
    alter table(:notifications) do
      add :group_key, :text
    end

    create index(:notifications, [:user_id, :group_key, "inserted_at DESC", "id DESC"],
             name: :notifications_live_group_index,
             where: "deleted_at IS NULL AND group_key IS NOT NULL"
           )

    execute(backfill_sql())
  end

  def down do
    drop_if_exists index(:notifications, [:user_id, :group_key],
                     name: :notifications_live_group_index
                   )

    alter table(:notifications) do
      remove :group_key
    end
  end

  @doc false
  # Public for the test that checks it writes the keys the app writes.
  def backfill_sql do
    conversation_cases =
      Enum.map_join(@conversation_rules, "\n", fn {type, field} ->
        "WHEN n.type = '#{type}' AND coalesce(n.payload->>'#{field}', '') <> '' " <>
          "THEN n.type || ':c:' || left(n.payload->>'#{field}', 120)"
      end)

    """
    WITH zones AS (
      SELECT
        n.id,
        (n.inserted_at AT TIME ZONE 'UTC') AS at_utc,
        coalesce(
          (SELECT s.timezone FROM organization_settings s
            WHERE s.organization_id = n.organization_id
              AND s.timezone_source IN ('confirmed', 'inferred')
              AND s.timezone IN (SELECT name FROM pg_timezone_names)
            LIMIT 1),
          'Europe/Athens'
        ) AS box_zone,
        coalesce(
          (SELECT u.time_zone FROM users u
            WHERE u.id = n.user_id
              AND u.time_zone IN (SELECT name FROM pg_timezone_names)),
          'Europe/Athens'
        ) AS person_zone
      FROM notifications n
    ),
    days AS (
      SELECT
        z.id,
        to_char((z.at_utc AT TIME ZONE z.box_zone)::date, 'YYYY-MM-DD') AS box_day,
        to_char((z.at_utc AT TIME ZONE z.person_zone)::date, 'YYYY-MM-DD') AS person_day
      FROM zones z
    )
    UPDATE notifications n
    SET group_key = CASE
      WHEN n.type IN (#{quoted(@never_types)}) THEN NULL
      #{conversation_cases}
      WHEN n.type IN (#{quoted(@personal_day_types)}) THEN n.type || ':p:d:' || d.person_day
      WHEN n.type IN (#{quoted(@subject_day_types)})
        AND left(n.payload->>'scheduled_for', 10) ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
        THEN n.type || ':o:' || coalesce(n.organization_id::text, '-') || ':d:' ||
          left(n.payload->>'scheduled_for', 10)
      ELSE n.type || ':o:' || coalesce(n.organization_id::text, '-') || ':d:' ||
        CASE WHEN n.organization_id IS NULL THEN d.person_day ELSE d.box_day END
    END
    FROM days d
    WHERE d.id = n.id
    """
  end

  defp quoted(types), do: Enum.map_join(types, ", ", &"'#{&1}'")
end

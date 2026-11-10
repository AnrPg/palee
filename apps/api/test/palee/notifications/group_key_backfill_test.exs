defmodule Palee.Notifications.GroupKeyBackfillTest do
  @moduledoc """
  ADR-600: the migration writes, for the notifications written before it,
  the same `group_key` the app writes from now on, so an older notification
  of today joins the stack of the new ones.
  """

  use Palee.DataCase, async: false

  import Palee.TestFixtures

  alias Palee.Notifications
  alias Palee.Organizations

  Code.require_file("priv/repo/migrations/20271112100000_notification_group_key.exs")
  alias Palee.Repo.Migrations.NotificationGroupKey

  test "the backfill writes the keys the app writes" do
    user = user_fixture()
    {:ok, box} = Organizations.create_organization(%{name: "Backfill Box"})

    samples = [
      %{type: :class_workout_missing, organization_id: box.id, payload: %{"class_name" => "A"}},
      %{type: :water_reminder, payload: %{}},
      %{type: :person_message, payload: %{"conversation_id" => "conv-1"}},
      %{type: :chat_message, organization_id: box.id, payload: %{}},
      %{type: :new_follower, organization_id: box.id, payload: %{"follow_id" => "f"}},
      %{
        type: :workout_changed,
        organization_id: box.id,
        payload: %{"scheduled_for" => "2026-11-12"}
      },
      %{type: :password_reset_completed, payload: %{}}
    ]

    expected =
      for sample <- samples do
        {:ok, notification} =
          Notifications.create_notification(Map.put(sample, :user_id, user.id))

        {notification.id, notification.group_key}
      end

    Palee.Repo.query!("UPDATE notifications SET group_key = NULL WHERE user_id = $1", [
      Ecto.UUID.dump!(user.id)
    ])

    Palee.Repo.query!(NotificationGroupKey.backfill_sql())

    for {id, key} <- expected do
      %{rows: [[backfilled]]} =
        Palee.Repo.query!("SELECT group_key FROM notifications WHERE id = $1", [
          Ecto.UUID.dump!(id)
        ])

      assert backfilled == key
    end

    assert Enum.count(expected, fn {_id, key} -> is_nil(key) end) == 1
  end
end

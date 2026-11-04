defmodule Palee.Notifications.Commands.RestoreNotification do
  @moduledoc """
  ADR-460: «Αναίρεση» of a delete, accepted only within the restore window
  (`NotificationFilter.restore_window_seconds/0`). After it, a deleted
  notification can never come back in any client.
  """

  alias Palee.Notifications.Domain.NotificationFilter
  alias Palee.Notifications.NotificationStore

  def call(user_id, notification_id, now \\ DateTime.utc_now()),
    do:
      NotificationStore.restore(
        user_id,
        notification_id,
        NotificationFilter.restorable_since(now)
      )
end

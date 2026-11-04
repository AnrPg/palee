defmodule Palee.Notifications.Commands.DeleteNotification do
  @moduledoc """
  ADR-460: the person deletes one of their notifications. The row is soft
  deleted (`deleted_at`), so no client shows it again; it may be restored
  for `NotificationFilter.restore_window_seconds/0` (the bell's «Αναίρεση»).
  """

  alias Palee.Notifications.NotificationStore

  def call(user_id, notification_id, now \\ DateTime.utc_now()),
    do: NotificationStore.soft_delete(user_id, notification_id, now)
end

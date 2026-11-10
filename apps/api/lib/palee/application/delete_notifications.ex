defmodule Palee.Application.DeleteNotifications do
  @moduledoc """
  ADR-460: «Διαγραφή ειδοποιήσεων» in Ρυθμίσεις: the ids picked, or every
  notification of a filter. Answers how many were deleted. ADR-600: the
  bell's trash on a stack deletes its filter (`group_key`), and `restore/2`
  brings them back within the restore window («Αναίρεση»).
  """

  alias Palee.Notifications

  def call(user_id, body), do: Notifications.delete_notifications(user_id, body)

  def restore(user_id, body), do: Notifications.restore_notifications(user_id, body)

  def restorable_for_seconds, do: Notifications.restore_window_seconds()
end

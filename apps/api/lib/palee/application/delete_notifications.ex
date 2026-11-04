defmodule Palee.Application.DeleteNotifications do
  @moduledoc """
  ADR-460: «Διαγραφή ειδοποιήσεων» in Ρυθμίσεις: the ids picked, or every
  notification of a filter. Answers how many were deleted. Not undoable.
  """

  alias Palee.Notifications

  def call(user_id, body), do: Notifications.delete_notifications(user_id, body)
end

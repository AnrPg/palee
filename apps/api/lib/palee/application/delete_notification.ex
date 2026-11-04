defmodule Palee.Application.DeleteNotification do
  @moduledoc """
  ADR-460: the bell's trash button and its «Αναίρεση»: one notification is
  deleted for the person (soft delete), and may be restored within a short
  window.
  """

  alias Palee.Notifications

  @doc "Answers how many seconds «Αναίρεση» may still restore it."
  def call(user_id, notification_id) do
    with :ok <- Notifications.delete_notification(user_id, notification_id) do
      {:ok, Notifications.restore_window_seconds()}
    end
  end

  def restore(user_id, notification_id),
    do: Notifications.restore_notification(user_id, notification_id)
end

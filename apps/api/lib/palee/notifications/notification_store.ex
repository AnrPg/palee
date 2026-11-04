defmodule Palee.Notifications.NotificationStore do
  @behaviour Palee.Notifications.Ports.NotificationStore

  alias Palee.Infrastructure.Tenancy.RepoContext

  def with_user_context(context, fun) when is_function(fun, 0),
    do: RepoContext.run(context, fun)

  defp adapter do
    Application.fetch_env!(:palee, :notification_store)
  end

  @impl true
  def create_notification(params), do: adapter().create_notification(params)

  @impl true
  def list_for_user(user_id), do: adapter().list_for_user(user_id)

  @impl true
  def list_inbox_page(user_id, opts), do: adapter().list_inbox_page(user_id, opts)

  @impl true
  def count_unread_inbox(user_id), do: adapter().count_unread_inbox(user_id)

  @impl true
  def count_inbox(user_id, filter), do: adapter().count_inbox(user_id, filter)

  @impl true
  def soft_delete(user_id, notification_id, at),
    do: adapter().soft_delete(user_id, notification_id, at)

  @impl true
  def soft_delete_ids(user_id, ids, at), do: adapter().soft_delete_ids(user_id, ids, at)

  @impl true
  def soft_delete_matching(user_id, filter, at),
    do: adapter().soft_delete_matching(user_id, filter, at)

  @impl true
  def restore(user_id, notification_id, deleted_since),
    do: adapter().restore(user_id, notification_id, deleted_since)

  @impl true
  def mark_all_read(user_id), do: adapter().mark_all_read(user_id)

  @impl true
  def mark_read(user_id, notification_id), do: adapter().mark_read(user_id, notification_id)

  @impl true
  def get_notification_organization_id(user_id, notification_id),
    do: adapter().get_notification_organization_id(user_id, notification_id)

  @impl true
  def delete_booking_pending_for_booking(booking_id),
    do: adapter().delete_booking_pending_for_booking(booking_id)

  @impl true
  def propagate_nickname_change(old_nickname, new_nickname),
    do: adapter().propagate_nickname_change(old_nickname, new_nickname)
end

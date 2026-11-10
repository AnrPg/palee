defmodule Palee.Notifications.Ports.NotificationStore do
  @callback create_notification(map()) ::
              {:ok, map() | :duplicate | :suppressed} | {:error, Ecto.Changeset.t()}
  @callback list_for_user(Ecto.UUID.t()) :: [map()]
  @callback list_inbox_page(Ecto.UUID.t(), keyword()) :: %{
              notifications: [map()],
              next_cursor: String.t() | nil
            }
  @callback count_unread_inbox(Ecto.UUID.t()) :: non_neg_integer()
  # ADR-600: unread notifications of one stack (the push says "+N more").
  @callback count_unread_in_group(Ecto.UUID.t(), String.t()) :: non_neg_integer()
  # ADR-600: the closed eye of a stack marks every notification a filter matches.
  @callback mark_read_matching(Ecto.UUID.t(), map()) :: non_neg_integer()
  # ADR-600: «Αναίρεση» of a stack's delete.
  @callback restore_matching(Ecto.UUID.t(), map(), DateTime.t()) :: non_neg_integer()
  # ADR-460: `filter` is a `Domain.NotificationFilter`; deleted rows are never counted.
  @callback count_inbox(Ecto.UUID.t(), map()) :: non_neg_integer()
  @callback soft_delete(Ecto.UUID.t(), Ecto.UUID.t(), DateTime.t()) :: boolean()
  @callback soft_delete_ids(Ecto.UUID.t(), [Ecto.UUID.t()], DateTime.t()) :: non_neg_integer()
  @callback soft_delete_matching(Ecto.UUID.t(), map(), DateTime.t()) :: non_neg_integer()
  @callback restore(Ecto.UUID.t(), Ecto.UUID.t(), DateTime.t()) :: boolean()
  @callback mark_all_read(Ecto.UUID.t()) :: non_neg_integer()
  @callback mark_read(Ecto.UUID.t(), Ecto.UUID.t()) :: boolean()
  @callback get_notification_organization_id(Ecto.UUID.t(), Ecto.UUID.t()) ::
              Ecto.UUID.t() | nil
  @callback delete_booking_pending_for_booking(Ecto.UUID.t()) :: :ok
  @callback propagate_nickname_change(String.t(), String.t()) :: :ok
end

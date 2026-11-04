defmodule Palee.Notifications.Commands.DeleteNotifications do
  @moduledoc """
  ADR-460: «Διαγραφή N ειδοποιήσεων» from Ρυθμίσεις: the ids picked, or every
  notification a filter matches (so "select all" never ships ids). Not
  undoable: there is no restore for a bulk delete.
  """

  alias Palee.Notifications.Domain.NotificationFilter
  alias Palee.Notifications.NotificationStore

  def call(user_id, body, now \\ DateTime.utc_now()) do
    case NotificationFilter.parse_bulk(body, now) do
      {:ok, {:ids, ids}} ->
        {:ok, NotificationStore.soft_delete_ids(user_id, ids, now)}

      {:ok, {:filter, filter}} ->
        {:ok, NotificationStore.soft_delete_matching(user_id, filter, now)}

      {:error, _reason} = error ->
        error
    end
  end
end

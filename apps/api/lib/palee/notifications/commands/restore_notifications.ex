defmodule Palee.Notifications.Commands.RestoreNotifications do
  @moduledoc """
  ADR-600: «Αναίρεση» after the trash of a stack: every notification the
  filter matches that was deleted within the restore window comes back.
  Answers how many.
  """

  alias Palee.Notifications.Domain.NotificationFilter
  alias Palee.Notifications.NotificationStore

  def call(user_id, body, now \\ DateTime.utc_now()) do
    with {:ok, filter} <- parse(body, now) do
      {:ok,
       NotificationStore.restore_matching(
         user_id,
         filter,
         NotificationFilter.restorable_since(now)
       )}
    end
  end

  defp parse(body, now) when is_map(body) do
    case Map.get(body, :filter, Map.get(body, "filter")) do
      filter when is_map(filter) -> NotificationFilter.parse(filter, now)
      _missing -> {:error, :bad_request}
    end
  end

  defp parse(_body, _now), do: {:error, :bad_request}
end

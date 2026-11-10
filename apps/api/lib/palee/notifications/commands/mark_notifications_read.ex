defmodule Palee.Notifications.Commands.MarkNotificationsRead do
  @moduledoc """
  ADR-600: the closed eye of a stack in the bell marks every notification of
  the stack read: the body is `%{filter: %{group_key: ...}}`, any
  `Domain.NotificationFilter`. Answers how many were marked.
  """

  alias Palee.Notifications.Domain.NotificationFilter
  alias Palee.Notifications.NotificationStore

  def call(user_id, body, now \\ DateTime.utc_now()) do
    with {:ok, filter} <- parse(body, now) do
      {:ok, NotificationStore.mark_read_matching(user_id, filter)}
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

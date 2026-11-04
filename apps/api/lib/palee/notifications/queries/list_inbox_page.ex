defmodule Palee.Notifications.Queries.ListInboxPage do
  alias Palee.Notifications.Domain.{InboxCursor, NotificationFilter}
  alias Palee.Notifications.NotificationStore

  @default_limit 20
  @max_limit 50

  # ADR-460: `state`, `older_than_days` and `category` narrow the page (the
  # delete card of Ρυθμίσεις); `include_count` adds how many match in all.
  def call(user_id, params \\ %{}) do
    with {:ok, cursor} <- InboxCursor.decode(param(params, :cursor)),
         {:ok, limit} <- normalize_limit(param(params, :limit)),
         {:ok, filter} <- NotificationFilter.parse(params, DateTime.utc_now()) do
      page =
        NotificationStore.list_inbox_page(user_id, limit: limit, cursor: cursor, filter: filter)

      {:ok,
       %{
         notifications: page.notifications,
         next_cursor: page.next_cursor,
         matching_count: matching_count(user_id, filter, param(params, :include_count))
       }}
    end
  end

  defp matching_count(user_id, filter, include) when include in [true, "true"],
    do: NotificationStore.count_inbox(user_id, filter)

  defp matching_count(_user_id, _filter, _include), do: nil

  defp normalize_limit(nil), do: {:ok, @default_limit}

  defp normalize_limit(limit) when is_integer(limit) and limit > 0,
    do: {:ok, min(limit, @max_limit)}

  defp normalize_limit(limit) when is_binary(limit) do
    case Integer.parse(limit) do
      {parsed, ""} when parsed > 0 -> {:ok, min(parsed, @max_limit)}
      _ -> {:error, :bad_request}
    end
  end

  defp normalize_limit(_limit), do: {:error, :bad_request}

  defp param(params, key), do: Map.get(params, key) || Map.get(params, Atom.to_string(key))
end

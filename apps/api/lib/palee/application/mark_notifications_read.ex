defmodule Palee.Application.MarkNotificationsRead do
  alias Palee.Application.RecordAnalyticsEvent
  alias Palee.Notifications

  def call(user_id) do
    marked_count = Notifications.mark_all_read(user_id)

    if marked_count > 0 do
      RecordAnalyticsEvent.call_unsafe("notification_read", %{
        user_id: user_id,
        context_type: "notification_bulk_read",
        metadata: %{marked_count: marked_count}
      })
    end

    marked_count
  end

  @doc "ADR-600: a stack's closed eye: every notification of the filter."
  def call_matching(user_id, body) do
    with {:ok, marked_count} <- Notifications.mark_read_matching(user_id, body) do
      if marked_count > 0 do
        RecordAnalyticsEvent.call_unsafe("notification_read", %{
          user_id: user_id,
          context_type: "notification_stack_read",
          metadata: %{marked_count: marked_count}
        })
      end

      {:ok, marked_count}
    end
  end
end

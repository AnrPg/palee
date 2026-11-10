defmodule Palee.Infrastructure.Notifications.EctoNotificationStore do
  @behaviour Palee.Notifications.Ports.NotificationStore

  import Ecto.Query

  alias Palee.Notifications.Domain.{InboxCursor, NotificationGrouping, VisibleTypes}
  alias Palee.Notifications.Notification
  alias Palee.Infrastructure.Tenancy.RepoContext
  alias Palee.Repo

  # A duplicate `dedupe_key` (e.g. the same reminder job running on several
  # API pods at once) must not raise a unique violation: Postgres logs it as an
  # ERROR and it aborts any surrounding transaction. `DO UPDATE ... WHERE false`
  # skips the row without touching it and, unlike `DO NOTHING`, makes Ecto
  # report the skip (as a stale error on `:dedupe_key`), so callers still get
  # `{:ok, :duplicate}`.
  @dedupe_conflict_target {:unsafe_fragment, "(user_id, dedupe_key) WHERE dedupe_key IS NOT NULL"}

  @impl true
  def create_notification(params) do
    %Notification{}
    |> Notification.changeset(params)
    |> Repo.insert(
      on_conflict:
        from(n in Notification, update: [set: [dedupe_key: n.dedupe_key]], where: false),
      conflict_target: @dedupe_conflict_target,
      stale_error_field: :dedupe_key,
      stale_error_message: "has already been taken"
    )
    |> case do
      {:ok, %Notification{} = notification} ->
        {:ok, normalize_notification(notification)}

      {:error, %Ecto.Changeset{} = changeset} ->
        if Keyword.has_key?(changeset.errors, :dedupe_key) do
          {:ok, :duplicate}
        else
          {:error, changeset}
        end
    end
  end

  @impl true
  def list_for_user(user_id) do
    Notification
    |> scoped_to_user()
    |> where([notification], notification.user_id == ^user_id)
    |> not_deleted()
    |> order_by([notification], desc: notification.inserted_at)
    |> Repo.all()
    |> Enum.map(&normalize_notification/1)
  end

  @impl true
  def list_inbox_page(user_id, opts) do
    limit = Keyword.fetch!(opts, :limit)
    cursor = Keyword.get(opts, :cursor)
    filter = Keyword.get(opts, :filter)

    notifications =
      if Keyword.get(opts, :stacks, false),
        do: list_stacked(user_id, filter, cursor, limit),
        else: list_flat(user_id, filter, cursor, limit)

    {page_entries, next_cursor} = split_page(notifications, limit)

    %{
      notifications: page_entries,
      next_cursor: next_cursor
    }
  end

  defp list_flat(user_id, filter, cursor, limit) do
    user_id
    |> live_inbox()
    |> apply_filter(filter)
    |> maybe_apply_cursor(cursor)
    |> order_by([notification], desc: notification.inserted_at, desc: notification.id)
    |> limit(^limit_plus_one(limit))
    |> Repo.all()
    |> Enum.map(&normalize_notification/1)
  end

  # ADR-600: one row per stack (its newest notification, with how many it
  # holds and how many are unread), and every notification of a group too
  # small to stack. A stack sorts by its newest notification, so one that
  # gets a new notification moves back to the top. The cursor pages over
  # these rows exactly as over single notifications.
  defp list_stacked(user_id, filter, cursor, limit) do
    ranked =
      user_id
      |> live_inbox()
      |> apply_filter(filter)
      |> select([n], %{
        id: n.id,
        stack_size:
          fragment(
            "count(*) OVER (PARTITION BY coalesce(?, ?::text))",
            n.group_key,
            n.id
          ),
        stack_unread:
          fragment(
            "count(*) FILTER (WHERE ? IS NULL) OVER (PARTITION BY coalesce(?, ?::text))",
            n.read_at,
            n.group_key,
            n.id
          ),
        stack_rank:
          fragment(
            "row_number() OVER (PARTITION BY coalesce(?, ?::text) ORDER BY ? DESC, ? DESC)",
            n.group_key,
            n.id,
            n.inserted_at,
            n.id
          )
      })

    min_size = NotificationGrouping.min_stack_size()

    Notification
    |> scoped_to_user()
    |> join(:inner, [notification], r in subquery(ranked), on: r.id == notification.id)
    |> where([_notification, r], r.stack_size < ^min_size or r.stack_rank == 1)
    |> maybe_apply_cursor(cursor)
    |> order_by([notification], desc: notification.inserted_at, desc: notification.id)
    |> limit(^limit_plus_one(limit))
    |> select([notification, r], {notification, r.stack_size, r.stack_unread})
    |> Repo.all()
    |> Enum.map(fn {notification, size, unread} ->
      notification
      |> normalize_notification()
      |> Map.put(:stack, stack(notification.group_key, size, unread, min_size))
    end)
  end

  defp stack(group_key, size, unread, min_size) when is_binary(group_key) and size >= min_size,
    do: %{key: group_key, count: size, unread_count: unread}

  defp stack(_group_key, _size, _unread, _min_size), do: nil

  @impl true
  def count_unread_in_group(_user_id, nil), do: 0

  def count_unread_in_group(user_id, group_key) do
    user_id
    |> live_inbox()
    |> where([n], n.group_key == ^group_key and is_nil(n.read_at))
    |> Repo.aggregate(:count)
  end

  @impl true
  def mark_read_matching(user_id, filter) do
    user_id
    |> live_inbox()
    |> apply_filter(filter)
    |> where([n], is_nil(n.read_at))
    |> Repo.update_all(set: [read_at: current_timestamp()])
    |> elem(0)
  end

  @impl true
  def restore_matching(user_id, filter, deleted_since) do
    Notification
    |> scoped_to_user()
    |> where([n], n.user_id == ^user_id and n.deleted_at >= ^deleted_since)
    |> apply_filter(filter)
    |> Repo.update_all(set: [deleted_at: nil])
    |> elem(0)
  end

  @impl true
  def count_unread_inbox(user_id) do
    user_id
    |> live_inbox()
    |> where([notification], is_nil(notification.read_at))
    |> Repo.aggregate(:count)
  end

  @impl true
  def count_inbox(user_id, filter) do
    user_id
    |> live_inbox()
    |> apply_filter(filter)
    |> Repo.aggregate(:count)
  end

  @impl true
  def mark_all_read(user_id) do
    user_id
    |> live_inbox()
    |> where([notification], is_nil(notification.read_at))
    |> Repo.update_all(set: [read_at: current_timestamp()])
    |> elem(0)
  end

  # ADR-460: a retried delete of a row already deleted still answers true,
  # without moving its `deleted_at` (and so its restore window).
  @impl true
  def soft_delete(user_id, notification_id, at) do
    {count, _rows} =
      user_id
      |> live_inbox()
      |> where([notification], notification.id == ^notification_id)
      |> Repo.update_all(set: [deleted_at: at])

    count == 1 or deleted?(user_id, notification_id)
  end

  @impl true
  def soft_delete_ids(user_id, ids, at) do
    user_id
    |> live_inbox()
    |> where([notification], notification.id in ^ids)
    |> Repo.update_all(set: [deleted_at: at])
    |> elem(0)
  end

  @impl true
  def soft_delete_matching(user_id, filter, at) do
    user_id
    |> live_inbox()
    |> apply_filter(filter)
    |> Repo.update_all(set: [deleted_at: at])
    |> elem(0)
  end

  @impl true
  def restore(user_id, notification_id, deleted_since) do
    {count, _rows} =
      Notification
      |> scoped_to_user()
      |> where(
        [notification],
        notification.user_id == ^user_id and notification.id == ^notification_id and
          notification.deleted_at >= ^deleted_since
      )
      |> Repo.update_all(set: [deleted_at: nil])

    count == 1
  end

  @impl true
  def mark_read(user_id, notification_id) do
    case Notification
         |> scoped_to_user()
         |> not_deleted()
         |> Repo.get_by(id: notification_id, user_id: user_id) do
      nil ->
        false

      %Notification{read_at: nil} = notification ->
        notification
        |> Ecto.Changeset.change(read_at: current_timestamp())
        |> Repo.update()
        |> case do
          {:ok, _notification} -> true
          {:error, _changeset} -> false
        end

      %Notification{} ->
        true
    end
  end

  @impl true
  def get_notification_organization_id(user_id, notification_id) do
    Notification
    |> scoped_to_user()
    |> where([n], n.user_id == ^user_id and n.id == ^notification_id)
    |> not_deleted()
    |> select([n], n.organization_id)
    |> Repo.one()
  end

  @impl true
  def delete_booking_pending_for_booking(booking_id) do
    Notification
    |> scoped_to_organization_or_unattributed()
    |> where(
      [n],
      n.type == :booking_pending and
        fragment("(?->>'booking_id')::text = ?", n.payload, ^booking_id)
    )
    |> Repo.delete_all()

    :ok
  end

  # TD-092 / ADR-131: the rows belong to many recipients and RLS is owner-only,
  # so the rewrite goes through the rename-gated SECURITY DEFINER helper.
  @impl true
  def propagate_nickname_change(old_nickname, new_nickname) do
    Repo.query!("SELECT palee_propagate_notification_nickname($1, $2)", [
      old_nickname,
      new_nickname
    ])

    :ok
  end

  # ADR-460: what any client may see of a person's inbox: their own rows,
  # not deleted, not the delivery records other screens show (VisibleTypes).
  defp live_inbox(user_id) do
    Notification
    |> scoped_to_user()
    |> where([notification], notification.user_id == ^user_id)
    |> not_deleted()
    |> where(
      [notification],
      fragment("? <> ALL(?)", notification.type, ^VisibleTypes.hidden_inbox_types())
    )
  end

  defp not_deleted(query), do: where(query, [notification], is_nil(notification.deleted_at))

  defp deleted?(user_id, notification_id) do
    Notification
    |> scoped_to_user()
    |> where(
      [n],
      n.user_id == ^user_id and n.id == ^notification_id and not is_nil(n.deleted_at)
    )
    |> Repo.exists?()
  end

  # A `Domain.NotificationFilter` (ADR-460); nil is no filter.
  defp apply_filter(query, nil), do: query

  defp apply_filter(query, filter) do
    query
    |> filter_read(filter.read_only)
    |> filter_inserted_before(filter.inserted_before)
    |> filter_types(filter.types)
    |> filter_group(Map.get(filter, :group_key))
  end

  defp filter_group(query, nil), do: query
  defp filter_group(query, group_key), do: where(query, [n], n.group_key == ^group_key)

  defp filter_read(query, true), do: where(query, [n], not is_nil(n.read_at))
  defp filter_read(query, _all), do: query

  defp filter_inserted_before(query, nil), do: query

  defp filter_inserted_before(query, %NaiveDateTime{} = before),
    do: where(query, [n], n.inserted_at < ^before)

  defp filter_types(query, nil), do: query

  defp filter_types(query, types) when is_list(types),
    do: where(query, [n], fragment("? = ANY(?)", n.type, ^types))

  defp maybe_apply_cursor(query, nil), do: query

  # The cursor carries a UTC DateTime; `inserted_at` is a naive (UTC) column.
  defp maybe_apply_cursor(query, %{inserted_at: %DateTime{} = at, id: id}) do
    inserted_at = at |> InboxCursor.to_utc() |> DateTime.to_naive()

    where(
      query,
      [notification],
      notification.inserted_at < ^inserted_at or
        (notification.inserted_at == ^inserted_at and notification.id < ^id)
    )
  end

  defp split_page(notifications, limit) do
    {entries, overflow} = Enum.split(notifications, limit)

    next_cursor =
      case {entries, overflow} do
        {[], _overflow} ->
          nil

        {_entries, []} ->
          nil

        {entries, [_next | _rest]} ->
          last_entry = List.last(entries)
          InboxCursor.encode(%{inserted_at: last_entry.inserted_at, id: last_entry.id})
      end

    {entries, next_cursor}
  end

  defp limit_plus_one(limit), do: limit + 1

  defp current_timestamp do
    DateTime.utc_now() |> DateTime.truncate(:second)
  end

  defp normalize_notification(%Notification{} = notification) do
    %{
      id: notification.id,
      user_id: notification.user_id,
      # The inbox deliberately spans organizations (F-28), so clients need the
      # origin in order to mark anything raised outside the active tenant.
      organization_id: notification.organization_id,
      type: to_string(notification.type),
      payload: notification.payload || %{},
      # ADR-600: similar notifications share it (nil: never stacked).
      group_key: notification.group_key,
      read_at: notification.read_at,
      # Stored naive (UTC); sent with its offset so clients never read it as local time.
      inserted_at: InboxCursor.to_utc(notification.inserted_at)
    }
  end

  defp scoped_to_user(query) do
    case RepoContext.current_setting("app.user_id") do
      user_id when is_binary(user_id) -> where(query, [row], row.user_id == ^user_id)
      _missing_scope -> where(query, [row], false)
    end
  end

  # Booking notices written before TD-092 carry no organization; booking ids are
  # globally unique, so such a row can only belong to this booking.
  defp scoped_to_organization_or_unattributed(query) do
    case RepoContext.current_setting("app.organization_id") do
      organization_id when is_binary(organization_id) ->
        where(
          query,
          [row],
          row.organization_id == ^organization_id or is_nil(row.organization_id)
        )

      _missing_scope ->
        where(query, [row], false)
    end
  end
end

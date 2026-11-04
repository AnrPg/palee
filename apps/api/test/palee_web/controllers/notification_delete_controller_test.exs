defmodule PaleeWeb.NotificationDeleteControllerTest do
  # ADR-460: deleting notifications (soft delete) from the bell and Ρυθμίσεις.
  use PaleeWeb.ConnCase, async: false

  alias Palee.Notifications

  import Palee.TestFixtures

  setup do
    user = user_fixture()

    conn =
      build_conn()
      |> put_bearer_token(user)
      |> Plug.Conn.put_req_header("content-type", "application/json")

    {:ok, conn: conn, user: user}
  end

  defp notify(user, type, attrs \\ %{}) do
    {:ok, notification} =
      Notifications.create_notification(
        Map.merge(%{user_id: user.id, type: type, payload: %{url: "/schedule"}}, attrs)
      )

    notification
  end

  defp read_now, do: DateTime.utc_now() |> DateTime.truncate(:second)

  defp age(notification, days) do
    Palee.Repo.query!(
      "UPDATE notifications SET inserted_at = now() - make_interval(days => $1) WHERE id = $2",
      [days, Ecto.UUID.dump!(notification.id)]
    )
  end

  defp list_ids(conn, query \\ "") do
    conn
    |> get("/api/notifications#{query}")
    |> json_response(200)
    |> Map.fetch!("notifications")
    |> Enum.map(& &1["id"])
  end

  test "a deleted notification leaves the list and the unread count", %{conn: conn, user: user} do
    kept = notify(user, :booking_approved)
    deleted = notify(user, :booking_pending)

    response = conn |> delete("/api/notifications/#{deleted.id}") |> json_response(200)
    assert response["deleted"] == true
    assert response["restorable_for_seconds"] == Notifications.restore_window_seconds()

    inbox = conn |> get("/api/notifications") |> json_response(200)
    assert Enum.map(inbox["notifications"], & &1["id"]) == [kept.id]
    assert inbox["unread_count"] == 1

    assert %{"unread_count" => 1} =
             conn |> get("/api/notifications/unread-count") |> json_response(200)

    # Neither read-all nor a single read touches it again.
    assert %{"marked_count" => 1} =
             conn |> post("/api/notifications/read-all") |> json_response(200)

    assert conn |> post("/api/notifications/#{deleted.id}/read") |> json_response(404)

    # The row is kept for the GDPR export, with its deletion time.
    %{rows: [[deleted_at]]} =
      Palee.Repo.query!("SELECT deleted_at FROM notifications WHERE id = $1", [
        Ecto.UUID.dump!(deleted.id)
      ])

    assert deleted_at
  end

  test "deleting is idempotent and refuses someone else's notification", %{
    conn: conn,
    user: user
  } do
    mine = notify(user, :booking_approved)
    theirs = notify(user_fixture(), :booking_approved)

    assert conn |> delete("/api/notifications/#{mine.id}") |> json_response(200)
    assert conn |> delete("/api/notifications/#{mine.id}") |> json_response(200)
    assert conn |> delete("/api/notifications/#{theirs.id}") |> json_response(404)
    assert conn |> delete("/api/notifications/#{Ecto.UUID.generate()}") |> json_response(404)
  end

  test "«Αναίρεση» restores within the window only", %{conn: conn, user: user} do
    notification = notify(user, :booking_approved)
    other = notify(user, :booking_approved)

    assert conn |> delete("/api/notifications/#{notification.id}") |> json_response(200)

    assert %{"restored" => true} =
             conn |> post("/api/notifications/#{notification.id}/restore") |> json_response(200)

    assert notification.id in list_ids(conn)

    # A notification never deleted cannot be "restored".
    assert %{"code" => "notification_not_restorable"} =
             conn |> post("/api/notifications/#{other.id}/restore") |> json_response(410)

    # After the window it is gone for good.
    assert conn |> delete("/api/notifications/#{notification.id}") |> json_response(200)

    Palee.Repo.query!(
      "UPDATE notifications SET deleted_at = deleted_at - make_interval(secs => $1) WHERE id = $2",
      [Notifications.restore_window_seconds() + 5, Ecto.UUID.dump!(notification.id)]
    )

    assert conn |> post("/api/notifications/#{notification.id}/restore") |> json_response(410)
    refute notification.id in list_ids(conn)
  end

  test "the list narrows by state, age and category and counts the matches", %{
    conn: conn,
    user: user
  } do
    read_booking = notify(user, :booking_approved, %{read_at: read_now()})
    unread_booking = notify(user, :booking_approved)
    old_message = notify(user, :person_message, %{payload: %{url: "/messages"}})
    age(old_message, 40)

    assert %{"matching_count" => nil} = conn |> get("/api/notifications") |> json_response(200)

    read = conn |> get("/api/notifications?state=read&include_count=true") |> json_response(200)
    assert Enum.map(read["notifications"], & &1["id"]) == [read_booking.id]
    assert read["matching_count"] == 1

    assert list_ids(conn, "?older_than_days=30") == [old_message.id]

    assert Enum.sort(list_ids(conn, "?category=bookings")) ==
             Enum.sort([read_booking.id, unread_booking.id])

    assert conn |> get("/api/notifications?category=nope") |> json_response(422)
  end

  test "bulk delete by ids touches only the user's own", %{conn: conn, user: user} do
    a = notify(user, :booking_approved)
    b = notify(user, :booking_approved)
    c = notify(user, :booking_approved)
    theirs = notify(user_fixture(), :booking_approved)

    assert %{"deleted_count" => 2} =
             conn
             |> post("/api/notifications/delete", %{ids: [a.id, b.id, theirs.id]})
             |> json_response(200)

    assert list_ids(conn) == [c.id]
  end

  test "bulk delete by filter deletes exactly what the filter lists", %{conn: conn, user: user} do
    read_old = notify(user, :booking_approved, %{read_at: read_now()})
    age(read_old, 45)
    read_new = notify(user, :booking_approved, %{read_at: read_now()})
    unread_old = notify(user, :booking_approved)
    age(unread_old, 45)

    assert %{"deleted_count" => 1} =
             conn
             |> post("/api/notifications/delete", %{
               filter: %{state: "read", older_than_days: 30}
             })
             |> json_response(200)

    assert Enum.sort(list_ids(conn)) == Enum.sort([read_new.id, unread_old.id])

    assert %{"deleted_count" => 2} =
             conn |> post("/api/notifications/delete", %{filter: %{}}) |> json_response(200)

    assert list_ids(conn) == []
    assert %{"unread_count" => 0} = conn |> get("/api/notifications") |> json_response(200)
  end

  test "bulk delete refuses ids and a filter together, or neither", %{conn: conn, user: user} do
    a = notify(user, :booking_approved)

    assert conn
           |> post("/api/notifications/delete", %{ids: [a.id], filter: %{}})
           |> json_response(400)

    assert conn |> post("/api/notifications/delete", %{}) |> json_response(400)
    assert list_ids(conn) == [a.id]
  end
end

defmodule PaleeWeb.NotificationStackControllerTest do
  @moduledoc """
  ADR-600: similar notifications stack in the bell. The stacked inbox lists
  one row per stack (its newest notification with `stack`), every
  notification of a group smaller than the stack size, and keeps counting
  every notification as unread. A stack opens by `group_key`, its closed eye
  marks all of it read, its trash deletes all of it, and «Αναίρεση» brings
  all of it back. The push of a stack carries its tag and how many more.
  """

  use PaleeWeb.ConnCase, async: false
  use Oban.Testing, repo: Palee.Repo

  import Palee.TestFixtures

  alias Palee.FakeNativePushSender
  alias Palee.Notifications
  alias Palee.Notifications.Commands.DispatchNotification
  alias Palee.Notifications.Domain.NotificationGrouping
  alias Palee.Organizations
  alias Palee.Workers.NativePushDispatchJob

  setup do
    user = user_fixture()
    {:ok, box} = Organizations.create_organization(%{name: "Stack Box"})

    conn =
      build_conn()
      |> put_bearer_token(user)
      |> Plug.Conn.put_req_header("content-type", "application/json")

    {:ok, conn: conn, user: user, box: box}
  end

  defp notify(user, type, attrs \\ %{}) do
    {:ok, notification} =
      Notifications.create_notification(
        Map.merge(%{user_id: user.id, type: type, payload: %{"url" => "/admin"}}, attrs)
      )

    notification
  end

  defp missing_wod(user, box, class_name) do
    notify(user, :class_workout_missing, %{
      organization_id: box.id,
      payload: %{"class_name" => class_name, "url" => "/admin/schedule"}
    })
  end

  # Rows written in one test second tie on `inserted_at` (second precision);
  # spreading them makes "newest" deterministic.
  defp at_seconds_ago(notification, seconds) do
    Palee.Repo.query!(
      "UPDATE notifications SET inserted_at = now() - make_interval(secs => $1) WHERE id = $2",
      [seconds, Ecto.UUID.dump!(notification.id)]
    )

    notification
  end

  defp inbox(conn, query \\ "stacks=true") do
    conn |> get("/api/notifications?#{query}") |> json_response(200)
  end

  test "similar notifications of the same box and day share one group key", %{
    user: user,
    box: box
  } do
    first = missing_wod(user, box, "CrossFit 07:00")
    second = missing_wod(user, box, "CrossFit 08:00")
    other_type = notify(user, :inventory_stock_low, %{organization_id: box.id})

    assert first.group_key == second.group_key
    assert first.group_key =~ "class_workout_missing:o:#{box.id}:d:"
    refute other_type.group_key == first.group_key
  end

  test "the stacked inbox shows one row per stack and counts every notification", %{
    conn: conn,
    user: user,
    box: box
  } do
    members =
      for {name, ago} <- [{"07:00", 40}, {"08:00", 30}, {"09:00", 20}, {"10:00", 10}],
          do: box |> then(&missing_wod(user, &1, name)) |> at_seconds_ago(ago)

    single = notify(user, :payment_failed, %{organization_id: box.id}) |> at_seconds_ago(5)

    body = inbox(conn)
    assert body["unread_count"] == 5

    assert [single_row, stack_row] = body["notifications"]
    assert single_row["id"] == single.id
    assert single_row["stack"] == nil

    newest = List.last(members)
    assert stack_row["id"] == newest.id
    assert stack_row["stack"]["key"] == newest.group_key
    assert stack_row["stack"]["count"] == 4
    assert stack_row["stack"]["unread_count"] == 4

    # Without `stacks` the list is flat, as before.
    assert length(inbox(conn, "")["notifications"]) == 5
  end

  test "two similar notifications are not a stack yet", %{conn: conn, user: user, box: box} do
    missing_wod(user, box, "07:00") |> at_seconds_ago(20)
    missing_wod(user, box, "08:00") |> at_seconds_ago(10)

    rows = inbox(conn)["notifications"]
    assert length(rows) == 2
    assert Enum.all?(rows, &is_nil(&1["stack"]))
    assert NotificationGrouping.min_stack_size() == 3
  end

  test "a stack opens by its key, newest first", %{conn: conn, user: user, box: box} do
    ids =
      for {name, ago} <- [{"07:00", 30}, {"08:00", 20}, {"09:00", 10}],
          do: missing_wod(user, box, name) |> at_seconds_ago(ago) |> Map.fetch!(:id)

    notify(user, :payment_failed, %{organization_id: box.id})

    [%{"stack" => %{"key" => key}} | _] =
      inbox(conn)["notifications"] |> Enum.filter(& &1["stack"])

    listed =
      conn
      |> inbox("group_key=#{URI.encode_www_form(key)}")
      |> Map.fetch!("notifications")
      |> Enum.map(& &1["id"])

    assert listed == Enum.reverse(ids)
  end

  test "the closed eye of a stack marks all of it read", %{conn: conn, user: user, box: box} do
    for name <- ~w(07:00 08:00 09:00), do: missing_wod(user, box, name)
    other = notify(user, :payment_failed, %{organization_id: box.id})

    key =
      Notifications.list_for_user(user.id)
      |> Enum.find(&(&1.group_key =~ "class_workout"))
      |> Map.fetch!(:group_key)

    assert %{"marked_count" => 3} =
             conn
             |> post("/api/notifications/read", %{filter: %{group_key: key}})
             |> json_response(200)

    body = inbox(conn)
    assert body["unread_count"] == 1
    stack = Enum.find(body["notifications"], & &1["stack"])
    assert stack["stack"]["unread_count"] == 0
    assert Enum.find(body["notifications"], &(&1["id"] == other.id))["read_at"] == nil
  end

  test "a new similar notification brings a read stack back to the top as new", %{
    conn: conn,
    user: user,
    box: box
  } do
    for {name, ago} <- [{"07:00", 30}, {"08:00", 20}, {"09:00", 10}],
        do: missing_wod(user, box, name) |> at_seconds_ago(ago)

    later = notify(user, :payment_failed, %{organization_id: box.id}) |> at_seconds_ago(5)

    key =
      Notifications.list_for_user(user.id)
      |> Enum.find(&(&1.group_key =~ "class_workout"))
      |> Map.fetch!(:group_key)

    conn |> post("/api/notifications/read", %{filter: %{group_key: key}}) |> json_response(200)

    newest = missing_wod(user, box, "10:00")

    assert [top, second] = inbox(conn)["notifications"]
    assert top["id"] == newest.id
    assert top["stack"] == %{"key" => key, "count" => 4, "unread_count" => 1}
    assert second["id"] == later.id
  end

  test "the trash of a stack deletes all of it and «Αναίρεση» brings it back", %{
    conn: conn,
    user: user,
    box: box
  } do
    for name <- ~w(07:00 08:00 09:00), do: missing_wod(user, box, name)
    kept = notify(user, :payment_failed, %{organization_id: box.id})

    key =
      Notifications.list_for_user(user.id)
      |> Enum.find(&(&1.group_key =~ "class_workout"))
      |> Map.fetch!(:group_key)

    deleted =
      conn
      |> post("/api/notifications/delete", %{filter: %{group_key: key}})
      |> json_response(200)

    assert deleted["deleted_count"] == 3
    assert deleted["restorable_for_seconds"] == Notifications.restore_window_seconds()
    assert Enum.map(inbox(conn)["notifications"], & &1["id"]) == [kept.id]

    assert %{"restored_count" => 3} =
             conn
             |> post("/api/notifications/restore", %{filter: %{group_key: key}})
             |> json_response(200)

    assert length(inbox(conn)["notifications"]) == 2

    # After the window, nothing comes back.
    conn |> post("/api/notifications/delete", %{filter: %{group_key: key}}) |> json_response(200)

    Palee.Repo.query!(
      "UPDATE notifications SET deleted_at = now() - interval '1 hour' WHERE group_key = $1",
      [key]
    )

    assert %{"restored_count" => 0} =
             conn
             |> post("/api/notifications/restore", %{filter: %{group_key: key}})
             |> json_response(200)
  end

  test "a stack's read and restore need a filter", %{conn: conn} do
    assert conn |> post("/api/notifications/read", %{}) |> json_response(422)
    assert conn |> post("/api/notifications/restore", %{}) |> json_response(422)
  end

  test "the tabs filter by type on the server, stacks included", %{
    conn: conn,
    user: user,
    box: box
  } do
    for name <- ~w(07:00 08:00 09:00), do: missing_wod(user, box, name)
    approved = notify(user, :booking_approved, %{organization_id: box.id})

    rows = inbox(conn, "stacks=true&types=booking_approved,booking_rejected")["notifications"]
    assert Enum.map(rows, & &1["id"]) == [approved.id]

    assert conn |> get("/api/notifications?types=not_a_type") |> json_response(400)
  end

  test "pages walk over stacks without splitting one", %{conn: conn, user: user, box: box} do
    for {name, ago} <- [{"07:00", 40}, {"08:00", 30}, {"09:00", 20}],
        do: missing_wod(user, box, name) |> at_seconds_ago(ago)

    single = notify(user, :payment_failed, %{organization_id: box.id}) |> at_seconds_ago(50)

    first = inbox(conn, "stacks=true&limit=1")
    assert [%{"stack" => %{"count" => 3}}] = first["notifications"]
    assert is_binary(first["next_cursor"])

    second =
      inbox(conn, "stacks=true&limit=1&cursor=#{URI.encode_www_form(first["next_cursor"])}")

    assert Enum.map(second["notifications"], & &1["id"]) == [single.id]
    assert second["next_cursor"] == nil
  end

  test "account security notifications never stack", %{user: user} do
    notice = notify(user, :password_reset_completed)
    assert notice.group_key == nil
  end

  describe "push" do
    setup do
      start_supervised!(
        {Oban, Keyword.put(Application.fetch_env!(:palee, Oban), :testing, :manual)}
      )

      FakeNativePushSender.enable([:fcm])
      on_exit(fn -> FakeNativePushSender.disable() end)
      :ok
    end

    test "the push of a stack carries its tag and how many more are unread", %{
      user: user,
      box: box
    } do
      {:ok, install, :created} =
        Notifications.register_native_push_token(user.id, %{
          "provider" => "fcm",
          "platform" => "android",
          "token" => "fcm-" <> String.duplicate("s", 30)
        })

      payload = fn name ->
        %{
          organization_id: box.id,
          class_name: name,
          class_when: "10/11 07:00",
          url: "/admin/schedule"
        }
      end

      assert {:ok, first} =
               DispatchNotification.call(user.id, :class_workout_missing, payload.("A"), "en")

      assert {:ok, _second} =
               DispatchNotification.call(user.id, :class_workout_missing, payload.("B"), "en")

      assert {:ok, _third} =
               DispatchNotification.call(user.id, :class_workout_missing, payload.("C"), "en")

      jobs = all_enqueued(worker: NativePushDispatchJob, args: %{"token_id" => install.id})
      tag = NotificationGrouping.push_tag(first.group_key)

      assert Enum.all?(jobs, &(&1.args["payload"]["push_tag"] == tag))

      bodies = jobs |> Enum.map(& &1.args["payload"]["body"]) |> Enum.sort()
      assert Enum.count(bodies, &String.ends_with?(&1, "\n+2 more similar")) == 1
      assert Enum.count(bodies, &String.ends_with?(&1, "\n+1 more similar")) == 1

      # The stored notifications keep their own text.
      refute Enum.any?(
               Notifications.list_for_user(user.id),
               &(&1.payload["body"] =~ "more similar")
             )
    end
  end
end

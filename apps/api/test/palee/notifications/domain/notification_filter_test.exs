defmodule Palee.Notifications.Domain.NotificationFilterTest do
  use ExUnit.Case, async: true

  alias Palee.Notifications.Domain.NotificationFilter

  @now ~U[2026-11-04 12:00:00Z]

  test "an empty filter covers every notification" do
    assert NotificationFilter.parse(%{}, @now) == {:ok, NotificationFilter.all()}
  end

  test "parses state, age and category from string or atom keys" do
    assert {:ok, %{read_only: true, inserted_before: before, types: types}} =
             NotificationFilter.parse(
               %{"state" => "read", "older_than_days" => "30", category: "bookings"},
               @now
             )

    assert before == ~N[2026-10-05 12:00:00]
    assert "booking_approved" in types
  end

  test "ADR-600: parses a stack's group key and a list of types" do
    assert {:ok, %{group_key: "class_workout_missing:o:-:d:2026-11-10", types: nil}} =
             NotificationFilter.parse(
               %{"group_key" => "class_workout_missing:o:-:d:2026-11-10"},
               @now
             )

    assert {:ok, %{types: ["booking_approved", "class_cancelled"]}} =
             NotificationFilter.parse(%{types: "booking_approved,class_cancelled"}, @now)

    assert {:ok, %{types: ["booking_approved"]}} =
             NotificationFilter.parse(%{types: ["booking_approved"]}, @now)

    # With a category too, both must match.
    assert {:ok, %{types: ["booking_approved"]}} =
             NotificationFilter.parse(
               %{types: "booking_approved,water_reminder", category: "bookings"},
               @now
             )
  end

  test "ADR-600: refuses an unknown type or an empty group key" do
    assert NotificationFilter.parse(%{types: "booking_approved,nope"}, @now) ==
             {:error, :bad_request}

    assert NotificationFilter.parse(%{group_key: ""}, @now) == {:error, :bad_request}

    assert NotificationFilter.parse(%{group_key: String.duplicate("k", 401)}, @now) ==
             {:error, :bad_request}
  end

  test "refuses unknown values" do
    assert NotificationFilter.parse(%{state: "unread"}, @now) == {:error, :bad_request}
    assert NotificationFilter.parse(%{older_than_days: 0}, @now) == {:error, :bad_request}
    assert NotificationFilter.parse(%{older_than_days: "3x"}, @now) == {:error, :bad_request}
    assert NotificationFilter.parse(%{category: "nope"}, @now) == {:error, :bad_request}
  end

  test "a bulk delete names ids or a filter, never both" do
    id = Ecto.UUID.generate()

    assert NotificationFilter.parse_bulk(%{"ids" => [id, id]}, @now) == {:ok, {:ids, [id]}}

    assert {:ok, {:filter, %{read_only: true}}} =
             NotificationFilter.parse_bulk(%{filter: %{state: "read"}}, @now)

    assert NotificationFilter.parse_bulk(%{ids: [id], filter: %{}}, @now) ==
             {:error, :bad_request}

    assert NotificationFilter.parse_bulk(%{}, @now) == {:error, :bad_request}
    assert NotificationFilter.parse_bulk(%{ids: []}, @now) == {:error, :bad_request}
    assert NotificationFilter.parse_bulk(%{ids: ["x"]}, @now) == {:error, :bad_request}

    too_many = for _ <- 0..NotificationFilter.max_ids(), do: Ecto.UUID.generate()
    assert NotificationFilter.parse_bulk(%{ids: too_many}, @now) == {:error, :bad_request}
  end

  test "a delete is restorable within the window only" do
    window = NotificationFilter.restore_window_seconds()

    assert NotificationFilter.restorable?(DateTime.add(@now, -window, :second), @now)
    refute NotificationFilter.restorable?(DateTime.add(@now, -window - 1, :second), @now)
    refute NotificationFilter.restorable?(nil, @now)

    assert NotificationFilter.restorable_since(@now) ==
             DateTime.add(@now, -window, :second)
  end
end

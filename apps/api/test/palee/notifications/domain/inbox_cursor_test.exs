defmodule Palee.Notifications.Domain.InboxCursorTest do
  use ExUnit.Case, async: true

  alias Palee.Notifications.Domain.InboxCursor

  @id "6f1b5c1e-2d6a-4f5e-9a51-0c2b8f9d3a10"

  test "a naive (UTC) time round-trips as a UTC DateTime" do
    cursor = InboxCursor.encode(%{inserted_at: ~N[2026-11-02 09:30:00], id: @id})
    assert {:ok, %{inserted_at: at, id: @id}} = InboxCursor.decode(cursor)
    assert at == ~U[2026-11-02 09:30:00Z]
  end

  test "a DateTime round-trips unchanged" do
    cursor = InboxCursor.encode(%{inserted_at: ~U[2026-11-02 09:30:00.123456Z], id: @id})
    assert {:ok, %{inserted_at: ~U[2026-11-02 09:30:00.123456Z]}} = InboxCursor.decode(cursor)
  end

  test "a cursor written without an offset still reads as UTC" do
    legacy = Base.url_encode64("2026-11-02T09:30:00|#{@id}", padding: false)
    assert {:ok, %{inserted_at: ~U[2026-11-02 09:30:00Z]}} = InboxCursor.decode(legacy)
  end

  test "rubbish, a bad id or a bad time is refused" do
    assert InboxCursor.decode("%%%") == {:error, :invalid_cursor}

    assert InboxCursor.decode(Base.url_encode64("2026-11-02T09:30:00Z|nope", padding: false)) ==
             {:error, :invalid_cursor}

    assert InboxCursor.decode(Base.url_encode64("yesterday|#{@id}", padding: false)) ==
             {:error, :invalid_cursor}

    assert InboxCursor.decode(42) == {:error, :invalid_cursor}
  end

  test "nil and blank mean the first page" do
    assert InboxCursor.decode(nil) == {:ok, nil}
    assert InboxCursor.decode("") == {:ok, nil}
    assert InboxCursor.encode(nil) == nil
  end
end

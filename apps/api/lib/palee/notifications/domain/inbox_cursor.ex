defmodule Palee.Notifications.Domain.InboxCursor do
  @moduledoc """
  The inbox's keyset cursor: the last row's time and id, opaque to clients.

  The time is always written as UTC ISO 8601 and read back as a UTC
  `DateTime`, whether the row's column is `naive_datetime` (notifications
  store UTC without an offset) or `utc_datetime`. Encoding a naive time used
  to raise, which failed every inbox with more than one page.
  """

  @separator "|"

  def encode(nil), do: nil

  def encode(%{inserted_at: inserted_at, id: id}) when is_binary(id) do
    [inserted_at |> to_utc() |> DateTime.to_iso8601(), id]
    |> Enum.join(@separator)
    |> Base.url_encode64(padding: false)
  end

  def decode(nil), do: {:ok, nil}
  def decode(""), do: {:ok, nil}

  def decode(cursor) when is_binary(cursor) do
    with {:ok, decoded} <- Base.url_decode64(cursor, padding: false),
         [inserted_at, id] <- String.split(decoded, @separator, parts: 2),
         {:ok, datetime} <- parse_utc(inserted_at),
         {:ok, _uuid} <- Ecto.UUID.cast(id) do
      {:ok, %{inserted_at: datetime, id: id}}
    else
      _error -> {:error, :invalid_cursor}
    end
  end

  def decode(_cursor), do: {:error, :invalid_cursor}

  @doc "A stored time as a UTC `DateTime` (naive times are UTC by convention)."
  def to_utc(%DateTime{} = at), do: DateTime.shift_zone!(at, "Etc/UTC")
  def to_utc(%NaiveDateTime{} = at), do: DateTime.from_naive!(at, "Etc/UTC")

  defp parse_utc(text) do
    case DateTime.from_iso8601(text) do
      {:ok, datetime, _offset} ->
        {:ok, datetime}

      {:error, :missing_offset} ->
        with {:ok, naive} <- NaiveDateTime.from_iso8601(text), do: {:ok, to_utc(naive)}

      {:error, _reason} = error ->
        error
    end
  end
end

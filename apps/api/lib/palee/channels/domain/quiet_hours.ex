defmodule Palee.Channels.Domain.QuietHours do
  @moduledoc """
  Quiet hours on the box's clock (ADR-349 §2, ADR-176/179). Between
  `start` and `end` (minutes after local midnight; the window may cross
  midnight) a marketing message waits until the window ends. A new
  connection starts with 21:00–09:00 (ANR 2026-11-03, amending ADR-390);
  the box changes or closes them. Service messages (a class cancelled, a
  booking reminder) always go at once.
  """

  @doc "The window a new connection starts with: 21:00–09:00 (ANR 2026-11-03)."
  def initial, do: {21 * 60, 9 * 60}

  @doc "Whether quiet hours may hold a message of `purpose`: only marketing waits."
  def applies?("marketing"), do: true
  def applies?(_purpose), do: false

  @doc """
  When a message created at `now` may go: `now` itself, or the end of the
  current quiet window. `nil` start or end means no quiet hours.
  """
  @spec release_at(DateTime.t(), String.t(), integer() | nil, integer() | nil) :: DateTime.t()
  def release_at(%DateTime{} = now, _zone, start, finish)
      when is_nil(start) or is_nil(finish) or start == finish,
      do: now

  def release_at(%DateTime{} = now, zone, start, finish) do
    local = DateTime.shift_zone!(now, zone)
    minute = local.hour * 60 + local.minute

    cond do
      not quiet?(minute, start, finish) ->
        now

      minute >= finish and start > finish ->
        # After the start, before midnight: the window ends tomorrow.
        at_local(Date.add(DateTime.to_date(local), 1), finish, zone)

      true ->
        if start < finish or minute < finish,
          do: at_local(DateTime.to_date(local), finish, zone),
          else: at_local(Date.add(DateTime.to_date(local), 1), finish, zone)
    end
  end

  @doc "Whether `minute` of the local day falls inside the window."
  def quiet?(minute, start, finish) when start < finish, do: minute >= start and minute < finish
  def quiet?(minute, start, finish), do: minute >= start or minute < finish

  defp at_local(%Date{} = date, minute, zone) do
    naive = NaiveDateTime.new!(date, Time.new!(div(minute, 60), rem(minute, 60), 0))

    case DateTime.from_naive(naive, zone) do
      {:ok, at} -> DateTime.shift_zone!(at, "Etc/UTC")
      {:ambiguous, first, _second} -> DateTime.shift_zone!(first, "Etc/UTC")
      {:gap, _before, after_gap} -> DateTime.shift_zone!(after_gap, "Etc/UTC")
    end
  end

  @doc "Validates a window given as \"HH:MM\" strings (or nils to switch it off)."
  def parse(nil, nil), do: {:ok, {nil, nil}}

  def parse(start, finish) when is_binary(start) and is_binary(finish) do
    with {:ok, a} <- minute(start), {:ok, b} <- minute(finish) do
      {:ok, {a, b}}
    end
  end

  def parse(_start, _finish), do: {:error, :invalid_quiet_hours}

  defp minute(<<h::binary-size(2), ":", m::binary-size(2)>>) do
    with {hour, ""} when hour in 0..23 <- Integer.parse(h),
         {min, ""} when min in 0..59 <- Integer.parse(m) do
      {:ok, hour * 60 + min}
    else
      _invalid -> {:error, :invalid_quiet_hours}
    end
  end

  defp minute(_value), do: {:error, :invalid_quiet_hours}

  @doc "\"HH:MM\" of a minute of the day, or nil."
  def format(nil), do: nil

  def format(minute) when is_integer(minute),
    do:
      String.pad_leading(Integer.to_string(div(minute, 60)), 2, "0") <>
        ":" <> String.pad_leading(Integer.to_string(rem(minute, 60)), 2, "0")
end

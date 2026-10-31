defmodule Palee.Scheduling.Domain.ICalendar do
  @moduledoc """
  ADR-359 (CP-E4): iCalendar (RFC 5545) for the personal calendar feed and
  for one booking's invite.

  An event keeps one **UID** for its whole life (`class-<class id>@palee`
  for a seat, whatever happens to the booking), so a calendar that
  subscribed to the feed or imported the invite updates the same entry
  instead of adding a second one. **SEQUENCE** must grow with every change
  the attendee should notice; it is derived from the latest change of the
  class and the booking (`sequence/1`: seconds since 2026-01-01 UTC), so it
  needs no counter of its own and never goes backwards. A booking or class
  that was cancelled stays in the feed with `STATUS:CANCELLED` for the
  feed's window, which makes subscribed calendars remove it, and a single
  invite of it is sent with `METHOD:CANCEL`.

  Pure: callers pass `now`.
  """

  @epoch ~U[2026-01-01 00:00:00Z]

  @doc "SEQUENCE from the moments the event changed (nil ignored); 0 when none."
  @spec sequence([DateTime.t() | NaiveDateTime.t() | nil]) :: non_neg_integer()
  def sequence(moments) do
    moments
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&to_utc/1)
    |> Enum.map(&DateTime.diff(&1, @epoch, :second))
    |> Enum.max(fn -> 0 end)
    |> max(0)
  end

  @doc "`CONFIRMED`, `TENTATIVE` or `CANCELLED` for a seat and its class."
  @spec status(atom() | String.t(), DateTime.t() | nil) :: String.t()
  def status(_booking_status, %DateTime{}), do: "CANCELLED"

  def status(booking_status, nil) do
    case to_string(booking_status) do
      "approved" -> "CONFIRMED"
      status when status in ["pending", "waitlisted"] -> "TENTATIVE"
      _cancelled_or_rejected -> "CANCELLED"
    end
  end

  @doc """
  The calendar text. `events` are maps with `uid`, `title`, `description`
  and either `starts_at`/`ends_at`, `starts_on`/`ends_on` (all day) or
  `recurrence` + `starts_at` + `duration_minutes`; optional `status`,
  `sequence`, `last_modified`, `location`. Options: `method` (`PUBLISH`
  default, or `CANCEL`), `name` (calendar name).
  """
  @spec render([map()], DateTime.t(), keyword()) :: String.t()
  def render(events, %DateTime{} = now, opts \\ []) do
    lines =
      [
        "BEGIN:VCALENDAR",
        "VERSION:2.0",
        "PRODID:-//Palee//Calendar Feed//EN",
        "CALSCALE:GREGORIAN",
        "METHOD:#{Keyword.get(opts, :method, "PUBLISH")}",
        "X-WR-CALNAME:#{escape(Keyword.get(opts, :name, "Palee"))}",
        Enum.map(events, &event_lines(&1, now)),
        "END:VCALENDAR"
      ]
      |> List.flatten()
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&fold/1)

    Enum.join(lines, "\r\n") <> "\r\n"
  end

  defp event_lines(%{starts_at: starts_at, ends_at: ends_at} = event, now) do
    [
      "BEGIN:VEVENT",
      "UID:#{escape(event.uid)}",
      "DTSTAMP:#{format_datetime(now)}",
      "DTSTART:#{format_datetime(starts_at)}",
      "DTEND:#{format_datetime(ends_at)}",
      "SUMMARY:#{escape(event.title)}",
      "DESCRIPTION:#{escape(event.description)}"
    ] ++ optional_lines(event) ++ ["END:VEVENT"]
  end

  defp event_lines(%{recurrence: series, starts_at: starts_at} = event, now) do
    [
      "BEGIN:VEVENT",
      "UID:#{escape(event.uid)}",
      "DTSTAMP:#{format_datetime(now)}",
      "DTSTART;TZID=#{escape(series.timezone)}:#{format_zoned_datetime(starts_at, series.timezone)}",
      "DURATION:PT#{event.duration_minutes}M",
      recurrence_rule(series),
      excluded_dates(series),
      "SUMMARY:#{escape(event.title)}",
      "DESCRIPTION:#{escape(event.description)}"
    ] ++ optional_lines(event) ++ ["END:VEVENT"]
  end

  defp event_lines(%{starts_on: starts_on, ends_on: ends_on} = event, now) do
    [
      "BEGIN:VEVENT",
      "UID:#{escape(event.uid)}",
      "DTSTAMP:#{format_datetime(now)}",
      "DTSTART;VALUE=DATE:#{format_date(starts_on)}",
      "DTEND;VALUE=DATE:#{format_date(ends_on)}",
      "SUMMARY:#{escape(event.title)}",
      "DESCRIPTION:#{escape(event.description)}"
    ] ++ optional_lines(event) ++ ["END:VEVENT"]
  end

  defp optional_lines(event) do
    [
      line("LOCATION", Map.get(event, :location), &escape/1),
      line("STATUS", Map.get(event, :status), & &1),
      line("SEQUENCE", Map.get(event, :sequence), &Integer.to_string/1),
      line("LAST-MODIFIED", Map.get(event, :last_modified), &format_datetime/1)
    ]
  end

  defp line(_name, nil, _format), do: nil
  defp line(_name, "", _format), do: nil
  defp line(name, value, format), do: "#{name}:#{format.(value)}"

  defp recurrence_rule(series) do
    byday = series.weekdays |> Enum.map(&weekday_code/1) |> Enum.join(",")
    until_part = if series.ends_on, do: ";UNTIL=#{format_date(series.ends_on)}T235959Z", else: ""
    "RRULE:FREQ=WEEKLY;INTERVAL=1;BYDAY=#{byday}#{until_part}"
  end

  defp excluded_dates(%{excluded_dates: []}), do: nil
  defp excluded_dates(%{excluded_dates: nil}), do: nil

  defp excluded_dates(series) do
    dates =
      series.excluded_dates
      |> Enum.map(&format_local_datetime(&1, series.local_start_time))
      |> Enum.join(",")

    "EXDATE;TZID=#{escape(series.timezone)}:#{dates}"
  end

  defp weekday_code(1), do: "MO"
  defp weekday_code(2), do: "TU"
  defp weekday_code(3), do: "WE"
  defp weekday_code(4), do: "TH"
  defp weekday_code(5), do: "FR"
  defp weekday_code(6), do: "SA"
  defp weekday_code(7), do: "SU"

  defp to_utc(%DateTime{} = at), do: DateTime.shift_zone!(at, "Etc/UTC")
  defp to_utc(%NaiveDateTime{} = at), do: DateTime.from_naive!(at, "Etc/UTC")

  defp format_datetime(datetime) do
    datetime
    |> to_utc()
    |> Calendar.strftime("%Y%m%dT%H%M%SZ")
  end

  defp format_date(date), do: Calendar.strftime(date, "%Y%m%d")

  defp format_local_datetime(date, time) do
    Calendar.strftime(date, "%Y%m%d") <> "T" <> Calendar.strftime(time, "%H%M%S")
  end

  defp format_zoned_datetime(datetime, timezone) do
    datetime
    |> DateTime.shift_zone!(timezone)
    |> Calendar.strftime("%Y%m%dT%H%M%S")
  end

  @doc "Escapes text per RFC 5545 §3.3.11."
  def escape(value) do
    value
    |> to_string()
    |> String.replace("\\", "\\\\")
    |> String.replace(";", "\\;")
    |> String.replace(",", "\\,")
    |> String.replace("\r\n", "\\n")
    |> String.replace("\n", "\\n")
  end

  # RFC 5545 §3.1: lines longer than 75 octets are folded (CRLF + space),
  # never inside a UTF-8 character.
  @doc false
  def fold(line) when byte_size(line) <= 75, do: line

  def fold(line) do
    line
    |> String.graphemes()
    |> Enum.reduce({[], "", 75}, fn grapheme, {done, current, limit} ->
      if byte_size(current) + byte_size(grapheme) > limit,
        do: {[current | done], grapheme, 74},
        else: {done, current <> grapheme, limit}
    end)
    |> then(fn {done, current, _limit} -> Enum.reverse([current | done]) end)
    |> Enum.join("\r\n ")
  end
end

defmodule Palee.Scheduling.Domain.BookingInviteEmail do
  @moduledoc """
  ADR-392: when a booking is worth one email with its calendar invite
  attached, and which. Pure.

    * `:booked` – the seat is confirmed (booked with automatic confirmation,
      approved by staff, or promoted from the waiting list) and its class is
      live. A request still waiting for staff or a waiting-list place is not a
      seat yet, so it gets nothing.
    * `:changed` – the class of a confirmed seat moved (another time, length
      or branch), or a seat that already had its invite was confirmed again.
      Same UID, higher SEQUENCE: calendars update the entry.
    * `:cancelled` – the seat or its class was cancelled, by the person or by
      the box, and the seat had been confirmed or had an invite: the invite
      comes as `METHOD:CANCEL` and calendars remove the entry. A request that
      was never confirmed is withdrawn silently.

  The person's switch («Email κράτησης με ημερολόγιο», category `bookings`,
  channel `email`) is checked by the caller.
  """

  @type trigger :: :booked | :moved | :cancelled
  @type kind :: :booked | :changed | :cancelled

  @doc """
  What to send for a `trigger`. Facts: `status` (the booking's status now),
  `previous_status` (before a cancellation), `class_cancelled?`, and
  `sent_before?` (an invite of this booking was already emailed).
  """
  @spec decide(trigger(), map()) :: {:send, kind()} | :skip
  def decide(:booked, facts) do
    if confirmed_live?(facts),
      do: {:send, if(Map.get(facts, :sent_before?, false), do: :changed, else: :booked)},
      else: :skip
  end

  def decide(:moved, facts),
    do: if(confirmed_live?(facts), do: {:send, :changed}, else: :skip)

  def decide(:cancelled, facts) do
    if status_name(Map.get(facts, :previous_status)) == "approved" or
         Map.get(facts, :sent_before?, false),
       do: {:send, :cancelled},
       else: :skip
  end

  def decide(_trigger, _facts), do: :skip

  @doc """
  Whether an edit moved the class for the people booked in it: another start,
  length or branch. Other edits (coach, WOD, capacity, name) do not.
  """
  @spec moved?(map(), map()) :: boolean()
  def moved?(before, after_edit) do
    not same_moment?(Map.get(before, :scheduled_at), Map.get(after_edit, :scheduled_at)) or
      Map.get(before, :duration_minutes) != Map.get(after_edit, :duration_minutes) or
      Map.get(before, :location_id) != Map.get(after_edit, :location_id)
  end

  @doc """
  The outbox idempotency key: one email per booking, kind and state of the
  seat (`derived`, the SEQUENCE its class's and seat's latest change give),
  plus the SEQUENCE actually sent (`sequence/2`).
  """
  @spec idempotency_key(String.t(), kind(), non_neg_integer(), non_neg_integer()) :: String.t()
  def idempotency_key(booking_id, kind, derived, sequence),
    do: "#{key_prefix(booking_id)}#{kind}:#{derived}:#{sequence}"

  @doc """
  Whether this kind of email was already sent for this state of the seat
  (`sent_keys`: the idempotency keys of the booking's invites), so a repeated
  event never sends twice while a real change always does.
  """
  @spec already_sent?([String.t()], String.t(), kind(), non_neg_integer()) :: boolean()
  def already_sent?(sent_keys, booking_id, kind, derived) do
    prefix = "#{key_prefix(booking_id)}#{kind}:#{derived}:"
    Enum.any?(sent_keys, &String.starts_with?(to_string(&1), prefix))
  end

  @doc """
  The SEQUENCE to send: the derived one (ADR-359), but always above every
  invite of this booking already emailed, so a change within the same second
  still reads as newer to calendars.
  """
  @spec sequence(non_neg_integer(), [String.t()]) :: non_neg_integer()
  def sequence(derived, sent_keys) do
    sent_keys
    |> Enum.flat_map(fn key ->
      case key |> to_string() |> String.split(":") |> List.last() |> Integer.parse() do
        {number, ""} -> [number]
        _other -> []
      end
    end)
    |> Enum.max(fn -> -1 end)
    |> Kernel.+(1)
    |> max(derived)
  end

  @doc "The prefix of every invite email of one booking (`Email.list_by_idempotency_prefix/1`)."
  @spec key_prefix(String.t()) :: String.t()
  def key_prefix(booking_id), do: "booking_invite:#{booking_id}:"

  defp confirmed_live?(facts),
    do:
      status_name(Map.get(facts, :status)) == "approved" and
        not Map.get(facts, :class_cancelled?, false)

  defp status_name(nil), do: nil
  defp status_name(status), do: to_string(status)

  defp same_moment?(%DateTime{} = a, %DateTime{} = b), do: DateTime.compare(a, b) == :eq
  defp same_moment?(a, b), do: a == b
end

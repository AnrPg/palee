defmodule Palee.Coaching.Domain.CoachNotePolicy do
  @moduledoc """
  Who reads a coach's private notes (ADR-101): the author; owners always;
  admins only while the author lets admins read them. Nobody else, head
  coaches included. Reads by anyone but the author are logged, and the coach
  is told when an admin read a note.
  """

  # The roles that see the box's people (`view_directory`); never the janitor,
  # and never the accountant (ANR 2026-11-03).
  @staff_roles [:owner, :admin, :coach, :front_desk]

  @doc """
  `reader_roles` in the gym; `author_allows_admins` is the author's setting.
  ADR-359 (CP-E5): a note written for the `staff` audience is read by every
  staff member of the box; a `private` one follows ADR-101.
  """
  def readable?(note, reader_id, reader_roles, author_allows_admins) do
    cond do
      note.coach_user_id == reader_id -> true
      staff_note?(note) -> Enum.any?(reader_roles, &(&1 in @staff_roles))
      :owner in reader_roles -> true
      :admin in reader_roles -> author_allows_admins == true
      true -> false
    end
  end

  @doc "Only reads of someone else's private note are logged; staff notes are shared on purpose."
  def logged?(note, reader_id), do: note.coach_user_id != reader_id and not staff_note?(note)

  def staff_note?(note), do: Map.get(note, :audience) == "staff"

  @doc "Owners read without notifying the coach; admins notify."
  def notify_author?(note, reader_id, reader_roles),
    do: logged?(note, reader_id) and :owner not in reader_roles

  def can_edit?(note, user_id), do: note.coach_user_id == user_id
end

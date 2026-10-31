defmodule Palee.Application.CoachNotes do
  @moduledoc """
  Private coach notes about a client (ADR-101). Coaches write notes about
  their own clients; owners read every note; admins read a coach's notes
  while the coach allows it. Every read by someone other than the author is
  logged, and the coach is notified when an admin read one of their notes.
  """

  alias Palee.{Coaching, Identity, Notifications, Organizations}
  alias Palee.Application.AuthorizeClientAccess
  alias Palee.Coaching.Domain.CoachNotePolicy

  def list(context, client_id, now \\ DateTime.utc_now()) do
    with :ok <- readable_client(context, client_id) do
      roles = Organizations.roles_in(context)
      visibility = author_visibility(context, client_id)

      notes =
        context
        |> Coaching.list_client_notes(client_id)
        |> Enum.filter(
          &CoachNotePolicy.readable?(
            &1,
            context.user_id,
            roles,
            Map.get(visibility, &1.coach_user_id)
          )
        )

      log_reads(context, notes, roles, client_id, now)
      {:ok, with_nicknames(notes)}
    end
  end

  @doc """
  `subject` is `%{kind, id}` when the note is about one thing (ADR-140 §5).
  `audience` (ADR-359): `private` (default, a coach's note, ADR-101) or
  `staff` (an internal comment the box's staff read, front desk included,
  written by anyone who sees the member in the directory).
  """
  def create(context, client_id, body, subject \\ nil, audience \\ "private")

  def create(context, client_id, body, subject, audience) when audience in [nil, "private"] do
    with :ok <- Organizations.authorize_capability(context, :write_coach_notes),
         :ok <- AuthorizeClientAccess.call(context, :manage_coaching, client_id) do
      insert(context, client_id, body, subject, "private")
    end
  end

  def create(context, client_id, body, subject, "staff") do
    with :ok <- Organizations.authorize_capability(context, :view_directory),
         :ok <- AuthorizeClientAccess.call(context, :view_directory, client_id) do
      insert(context, client_id, body, subject, "staff")
    end
  end

  def create(_context, _client_id, _body, _subject, _audience),
    do: {:error, :invalid_note_audience}

  defp insert(context, client_id, body, subject, audience) do
    Coaching.create_note(context, %{
      coach_user_id: context.user_id,
      client_user_id: client_id,
      body: body,
      subject_kind: subject && subject.kind,
      subject_id: subject && subject.id,
      audience: audience
    })
  end

  def update(context, id, body) do
    with {:ok, note} <- own_note(context, id) do
      Coaching.update_note(context, note.id, %{body: body})
    end
  end

  def delete(context, id) do
    with {:ok, note} <- own_note(context, id) do
      Coaching.delete_note(context, note.id)
    end
  end

  @doc "Who read the coach's notes and when."
  def reads(context) do
    with :ok <- Organizations.authorize_capability(context, :write_coach_notes) do
      reads = Coaching.list_note_reads(context, context.user_id)

      nicknames =
        reads
        |> Enum.flat_map(&[&1.reader_user_id, &1.client_user_id])
        |> Enum.uniq()
        |> Identity.list_by_ids()
        |> Map.new(&{&1.id, &1.nickname})

      {:ok,
       Enum.map(reads, fn read ->
         Map.merge(read, %{
           reader_nickname: Map.get(nicknames, read.reader_user_id),
           client_nickname: Map.get(nicknames, read.client_user_id)
         })
       end)}
    end
  end

  defp readable_client(context, client_id) do
    cond do
      Organizations.can?(context, :read_coach_notes) ->
        :ok

      Organizations.can?(context, :write_coach_notes) ->
        AuthorizeClientAccess.call(context, :manage_coaching, client_id)

      # ADR-359: the front desk reads the box's staff notes (the policy
      # keeps private notes from them).
      Organizations.can?(context, :view_directory) ->
        AuthorizeClientAccess.call(context, :view_directory, client_id)

      true ->
        {:error, :forbidden}
    end
  end

  defp own_note(context, id) do
    case Coaching.get_note(context, id) do
      nil ->
        {:error, :not_found}

      note ->
        if CoachNotePolicy.can_edit?(note, context.user_id),
          do: {:ok, note},
          else: {:error, :forbidden}
    end
  end

  defp author_visibility(context, client_id) do
    context
    |> Coaching.list_client_notes(client_id)
    |> Enum.map(& &1.coach_user_id)
    |> Enum.uniq()
    |> Map.new(&{&1, Organizations.notes_visible_to_admins?(context.organization_id, &1)})
  end

  defp log_reads(context, notes, roles, client_id, now) do
    logged = Enum.filter(notes, &CoachNotePolicy.logged?(&1, context.user_id))
    Coaching.record_note_reads(context, Enum.map(logged, & &1.id), context.user_id, now)

    people = Identity.list_by_ids([context.user_id, client_id]) |> Map.new(&{&1.id, &1.nickname})

    logged
    |> Enum.filter(&CoachNotePolicy.notify_author?(&1, context.user_id, roles))
    |> Enum.each(fn note ->
      Notifications.process_event("coach_note_viewed", %{
        user_id: note.coach_user_id,
        organization_id: context.organization_id,
        note_id: note.id,
        reader_nickname: Map.get(people, context.user_id),
        client_nickname: Map.get(people, client_id),
        client_user_id: client_id,
        read_at: DateTime.to_iso8601(now)
      })
    end)
  end

  defp with_nicknames(notes) do
    nicknames =
      notes
      |> Enum.map(& &1.coach_user_id)
      |> Enum.uniq()
      |> Identity.list_by_ids()
      |> Map.new(&{&1.id, &1.nickname})

    Enum.map(notes, &Map.put(&1, :coach_nickname, Map.get(nicknames, &1.coach_user_id)))
  end
end

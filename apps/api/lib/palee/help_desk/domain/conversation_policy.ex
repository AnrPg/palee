defmodule Palee.HelpDesk.Domain.ConversationPolicy do
  @moduledoc """
  The rules of support conversations and tickets (ADR-363), pure.

  Conversation states:

    * `assistant` – the AI first line answers from the help centre;
    * `waiting_for_palee` – handed to the Palee team (a ticket is open);
    * `answered_by_palee` – the team replied; the person's next message
      sends it back to `waiting_for_palee`;
    * `resolved` – closed by the person or the team; a new message reopens
      it where it was (with the assistant, or with the team if it has a
      ticket).

  Ticket states: `open` (the team's turn), `waiting_on_box` (the person's
  turn), `solved`. Priorities: `normal`, `urgent`.
  """

  alias Palee.Llm.Domain.Untrusted

  @statuses ~w(assistant waiting_for_palee answered_by_palee resolved)
  @ticket_statuses ~w(open waiting_on_box solved)
  @priorities ~w(normal urgent)
  @max_message 2_000
  @max_note 1_000
  @screen ~r/^\/[A-Za-z0-9_\-\/.\[\]]{0,299}$/

  def statuses, do: @statuses
  def ticket_statuses, do: @ticket_statuses
  def priorities, do: @priorities

  @doc "A person's message, cleaned; `{:error, {:invalid_fields, _}}` when empty or too long."
  def message(text) when is_binary(text) do
    cleaned = String.trim(text)

    cond do
      cleaned == "" -> {:error, {:invalid_fields, %{message: ["required"]}}}
      String.length(cleaned) > @max_message -> {:error, {:invalid_fields, %{message: ["too_long"]}}}
      true -> {:ok, cleaned}
    end
  end

  def message(_text), do: {:error, {:invalid_fields, %{message: ["required"]}}}

  @doc "The screen path the person asked from (query string dropped), or nil."
  def screen(path) when is_binary(path) do
    path = path |> String.split(["?", "#"]) |> hd() |> String.trim()
    if Regex.match?(@screen, path), do: path
  end

  def screen(_path), do: nil

  @doc "A short subject from the first message."
  def subject(text), do: Untrusted.text(text, 80)

  @doc "The browser and app facts a ticket keeps (whitelisted, short strings)."
  def client_context(%{} = context) do
    context
    |> Map.new(fn {k, v} -> {to_string(k), v} end)
    |> Map.take(~w(app_version platform browser viewport))
    |> Map.new(fn {k, v} -> {k, Untrusted.text(v, 80)} end)
    |> Map.reject(fn {_k, v} -> v in [nil, ""] end)
  end

  def client_context(_context), do: %{}

  @doc "The state after the person writes."
  def after_person_message(%{status: "resolved"}, has_ticket?),
    do: if(has_ticket?, do: "waiting_for_palee", else: "assistant")

  def after_person_message(%{status: "answered_by_palee"}, _has_ticket?), do: "waiting_for_palee"
  def after_person_message(%{status: status}, _has_ticket?), do: status

  @doc "Whether the assistant answers in this state."
  def assistant_turn?(status), do: status == "assistant"

  @doc """
  The ticket made when the person hands the conversation over: the
  person's note (or their first question), the screen, what the assistant
  already tried. `{:error, _}` for a bad priority or note.
  """
  def ticket(conversation, messages, params) do
    note = Map.get(params, "note")
    priority = Map.get(params, "priority") || "normal"

    first =
      Enum.find_value(messages, "", fn
        %{author: "person", body: body} -> body
        _other -> nil
      end)

    cond do
      priority not in @priorities ->
        {:error, {:invalid_fields, %{priority: ["invalid"]}}}

      not (is_nil(note) or (is_binary(note) and String.length(note) <= @max_note)) ->
        {:error, {:invalid_fields, %{note: ["too_long"]}}}

      true ->
        summary =
          [note, first]
          |> Enum.filter(&(is_binary(&1) and String.trim(&1) != ""))
          |> Enum.map(&String.trim/1)
          |> Enum.uniq()
          |> Enum.join("\n\n")
          |> String.slice(0, @max_note)

        {:ok,
         %{
           conversation_id: conversation.id,
           requester_id: conversation.user_id,
           status: "open",
           priority: priority,
           summary: if(summary == "", do: conversation.subject, else: summary),
           screen_path: conversation.screen_path,
           locale: conversation.locale,
           client_context: client_context(Map.get(params, "client_context")),
           articles_tried: articles_tried(messages)
         }}
    end
  end

  @doc "The help articles the assistant cited in a conversation."
  def articles_tried(messages) do
    messages
    |> Enum.flat_map(fn message -> Map.get(message, :citations) || [] end)
    |> Enum.map(&(Map.get(&1, "slug") || Map.get(&1, :slug)))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.take(20)
  end

  @doc "Changes the Palee team may make to a ticket."
  def ticket_update(ticket, params, %DateTime{} = now) do
    status = Map.get(params, "status", ticket.status)
    priority = Map.get(params, "priority", ticket.priority)

    cond do
      status not in @ticket_statuses ->
        {:error, {:invalid_fields, %{status: ["invalid"]}}}

      priority not in @priorities ->
        {:error, {:invalid_fields, %{priority: ["invalid"]}}}

      true ->
        changes = %{status: status, priority: priority}

        changes =
          if Map.has_key?(params, "assignee_id"),
            do: Map.put(changes, :assignee_id, Map.get(params, "assignee_id")),
            else: changes

        {:ok, Map.put(changes, :solved_at, if(status == "solved", do: ticket.solved_at || now))}
    end
  end

  @doc "The conversation state that goes with a ticket state."
  def conversation_status_for_ticket("solved"), do: "resolved"
  def conversation_status_for_ticket("waiting_on_box"), do: "answered_by_palee"
  def conversation_status_for_ticket("open"), do: "waiting_for_palee"
end

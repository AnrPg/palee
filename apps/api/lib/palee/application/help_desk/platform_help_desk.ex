defmodule Palee.Application.HelpDesk.PlatformHelpDesk do
  @moduledoc """
  The Palee team's support queue (ADR-363), vendor console: tickets of
  every box, oldest open first (urgent ones on top), and per ticket the
  whole conversation, a reply and its state, priority and assignee.

  Reading a ticket's conversation is reading a box's data, so it is
  written to the vendors' audit log (`Organizations.record_platform_event`,
  ADR-273), and done in that box's session.
  """

  alias Palee.{HelpDesk, Organizations}
  alias Palee.Organizations.PlatformContext

  @max_reply 4_000

  def tickets(%PlatformContext{} = platform, params) do
    status = Map.get(params, "status") || Map.get(params, :status)

    if is_nil(status) or status in HelpDesk.ticket_statuses() do
      {:ok, %{tickets: platform |> HelpDesk.list_tickets(%{status: status}) |> Enum.map(&ticket/1)}}
    else
      {:error, {:invalid_fields, %{status: ["invalid"]}}}
    end
  end

  def tickets(_context, _params), do: {:error, :vendor_required}

  def show(%PlatformContext{} = platform, id) do
    with {:ok, ticket, box} <- load(platform, id),
         {:ok, _event} <-
           Organizations.record_platform_event(platform, ticket.organization_id, %{
             event: "help_desk_ticket_viewed",
             metadata: %{ticket_id: ticket.id}
           }) do
      {:ok, detail(box, ticket)}
    end
  end

  def show(_context, _id), do: {:error, :vendor_required}

  def reply(platform, id, params, now \\ DateTime.utc_now())

  def reply(%PlatformContext{} = platform, id, params, now) do
    body = params |> Map.get("body", Map.get(params, :body)) |> trimmed()
    status = Map.get(params, "status", Map.get(params, :status)) || "waiting_on_box"

    with :ok <- valid_reply(body, status),
         {:ok, ticket, box} <- load(platform, id),
         {:ok, _message} <-
           HelpDesk.add_message(box, %{
             conversation_id: ticket.conversation_id,
             author: "palee",
             author_id: platform.user_id,
             body: body,
             inserted_at: now
           }),
         {:ok, ticket} <-
           HelpDesk.update_ticket(box, ticket.id, %{
             status: status,
             first_response_at: ticket.first_response_at || now,
             solved_at: if(status == "solved", do: now),
             assignee_id: ticket.assignee_id || platform.user_id
           }),
         {:ok, _conversation} <-
           HelpDesk.update_conversation(box, ticket.conversation_id, %{
             status: HelpDesk.conversation_status_for_ticket(status),
             last_message_at: now
           }),
         {:ok, _event} <-
           Organizations.record_platform_event(platform, ticket.organization_id, %{
             event: "help_desk_ticket_replied",
             metadata: %{ticket_id: ticket.id, status: status}
           }) do
      {:ok, detail(box, ticket)}
    end
  end

  def reply(_context, _id, _params, _now), do: {:error, :vendor_required}

  def update(platform, id, params, now \\ DateTime.utc_now())

  def update(%PlatformContext{} = platform, id, params, now) do
    params = Map.new(params, fn {k, v} -> {to_string(k), v} end)

    with {:ok, ticket, box} <- load(platform, id),
         {:ok, changes} <- HelpDesk.ticket_update(ticket, params, now),
         {:ok, updated} <- HelpDesk.update_ticket(box, ticket.id, changes),
         {:ok, _conversation} <- sync_conversation(box, ticket, updated),
         {:ok, _event} <-
           Organizations.record_platform_event(platform, ticket.organization_id, %{
             event: "help_desk_ticket_updated",
             metadata: %{ticket_id: ticket.id, status: updated.status, priority: updated.priority}
           }) do
      {:ok, detail(box, updated)}
    end
  end

  def update(_context, _id, _params, _now), do: {:error, :vendor_required}

  defp sync_conversation(_box, %{status: same}, %{status: same}), do: {:ok, :unchanged}

  defp sync_conversation(box, _before, ticket),
    do:
      HelpDesk.update_conversation(box, ticket.conversation_id, %{
        status: HelpDesk.conversation_status_for_ticket(ticket.status)
      })

  defp load(platform, id) do
    with {:ok, id} <- uuid(id),
         %{} = ticket <- HelpDesk.get_ticket(platform, id),
         true <-
           Organizations.platform_organization_exists?(platform, ticket.organization_id) do
      {:ok, ticket, %{organization_id: ticket.organization_id, user_id: platform.user_id}}
    else
      _missing -> {:error, :not_found}
    end
  end

  defp detail(box, ticket) do
    conversation = HelpDesk.get_conversation(box, ticket.conversation_id)

    ticket
    |> ticket()
    |> Map.merge(%{
      conversation: %{
        id: conversation.id,
        status: conversation.status,
        subject: conversation.subject,
        started_at: conversation.inserted_at
      },
      messages:
        box
        |> HelpDesk.list_messages(ticket.conversation_id)
        |> Enum.map(fn message ->
          %{
            id: message.id,
            author: message.author,
            body: message.body,
            citations: message.citations || [],
            guide_id: message.guide_id,
            confident: message.confident,
            sent_at: message.inserted_at
          }
        end)
    })
  end

  defp ticket(ticket) do
    %{
      id: ticket.id,
      organization_id: ticket.organization_id,
      status: ticket.status,
      priority: ticket.priority,
      summary: ticket.summary,
      screen_path: ticket.screen_path,
      locale: ticket.locale,
      client_context: ticket.client_context || %{},
      articles_tried: ticket.articles_tried || [],
      requester_id: ticket.requester_id,
      assignee_id: ticket.assignee_id,
      first_response_at: ticket.first_response_at,
      solved_at: ticket.solved_at,
      opened_at: ticket.inserted_at,
      updated_at: ticket.updated_at
    }
  end

  defp valid_reply(body, status) do
    cond do
      body == "" -> {:error, {:invalid_fields, %{body: ["required"]}}}
      String.length(body) > @max_reply -> {:error, {:invalid_fields, %{body: ["too_long"]}}}
      status not in ["waiting_on_box", "solved"] -> {:error, {:invalid_fields, %{status: ["invalid"]}}}
      true -> :ok
    end
  end

  defp uuid(id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> {:ok, id}
      :error -> {:error, :not_found}
    end
  end

  defp trimmed(value) when is_binary(value), do: String.trim(value)
  defp trimmed(_value), do: ""
end

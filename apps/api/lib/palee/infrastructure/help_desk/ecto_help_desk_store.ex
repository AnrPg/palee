defmodule Palee.Infrastructure.HelpDesk.EctoHelpDeskStore do
  @moduledoc "Ecto adapter of `HelpDesk.Ports.HelpDeskStore` (ADR-363)."

  @behaviour Palee.HelpDesk.Ports.HelpDeskStore

  import Ecto.Query

  alias Palee.HelpDesk.{Conversation, Message, Ticket}
  alias Palee.Repo

  @impl true
  def create_conversation(%{organization_id: organization_id}, attrs) do
    %Conversation{organization_id: organization_id} |> Conversation.changeset(attrs) |> Repo.insert()
  end

  @impl true
  def get_conversation(%{organization_id: organization_id}, id) do
    Conversation
    |> where([c], c.organization_id == ^organization_id and c.id == ^id)
    |> Repo.one()
  end

  @impl true
  def list_conversations(%{organization_id: organization_id}, user_id) do
    Conversation
    |> where([c], c.organization_id == ^organization_id and c.user_id == ^user_id)
    |> order_by([c], desc: c.last_message_at)
    |> limit(50)
    |> Repo.all()
  end

  @impl true
  def update_conversation(context, id, changes) do
    case get_conversation(context, id) do
      nil -> {:error, :not_found}
      conversation -> conversation |> Conversation.changeset(changes) |> Repo.update()
    end
  end

  @impl true
  def add_message(%{organization_id: organization_id}, attrs) do
    %Message{organization_id: organization_id} |> Message.changeset(attrs) |> Repo.insert()
  end

  @impl true
  def list_messages(%{organization_id: organization_id}, conversation_id) do
    Message
    |> where([m], m.organization_id == ^organization_id and m.conversation_id == ^conversation_id)
    # A reply written in the same instant as the question still comes after it.
    |> order_by([m], asc: m.inserted_at, desc: m.author == "person", asc: m.id)
    |> Repo.all()
  end

  @impl true
  def count_person_messages_since(%{organization_id: organization_id}, user_id, since) do
    Message
    |> where(
      [m],
      m.organization_id == ^organization_id and m.author == "person" and m.author_id == ^user_id and
        m.inserted_at >= ^since
    )
    |> select([m], count(m.id))
    |> Repo.one()
  end

  @impl true
  def create_ticket(%{organization_id: organization_id}, attrs) do
    %Ticket{organization_id: organization_id} |> Ticket.changeset(attrs) |> Repo.insert()
  end

  @impl true
  def ticket_for_conversation(%{organization_id: organization_id}, conversation_id) do
    Ticket
    |> where([t], t.organization_id == ^organization_id and t.conversation_id == ^conversation_id)
    |> Repo.one()
  end

  @impl true
  def update_ticket(%{organization_id: organization_id}, id, changes) do
    case Repo.one(from t in Ticket, where: t.organization_id == ^organization_id and t.id == ^id) do
      nil -> {:error, :not_found}
      ticket -> ticket |> Ticket.changeset(changes) |> Repo.update()
    end
  end

  @impl true
  def list_tickets(_vendor, filters) do
    Ticket
    |> filter_status(Map.get(filters, :status))
    |> order_by([t], desc: t.priority == "urgent", asc: t.inserted_at)
    |> limit(^Map.get(filters, :limit, 100))
    |> Repo.all()
  end

  @impl true
  def get_ticket(_vendor, id), do: Repo.get(Ticket, id)

  defp filter_status(query, nil), do: query
  defp filter_status(query, status), do: where(query, [t], t.status == ^status)
end

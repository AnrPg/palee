defmodule Palee.HelpDesk.Ticket do
  @moduledoc "A conversation handed to the Palee team (ADR-363)."

  use Ecto.Schema
  import Ecto.Changeset

  alias Palee.HelpDesk.Domain.ConversationPolicy

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "help_desk_tickets" do
    field :organization_id, :binary_id
    field :conversation_id, :binary_id
    field :requester_id, :binary_id
    field :status, :string, default: "open"
    field :priority, :string, default: "normal"
    field :summary, :string
    field :screen_path, :string
    field :locale, :string
    field :client_context, :map, default: %{}
    field :articles_tried, {:array, :string}, default: []
    field :assignee_id, :binary_id
    field :first_response_at, :utc_datetime_usec
    field :solved_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  @fields ~w(conversation_id requester_id status priority summary screen_path locale client_context
             articles_tried assignee_id first_response_at solved_at)a

  def changeset(ticket, attrs) do
    ticket
    |> cast(attrs, @fields)
    |> validate_required([:conversation_id, :status, :priority, :summary, :locale])
    |> validate_inclusion(:status, ConversationPolicy.ticket_statuses())
    |> validate_inclusion(:priority, ConversationPolicy.priorities())
    |> unique_constraint(:conversation_id)
  end
end

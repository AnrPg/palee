defmodule Palee.HelpDesk.Conversation do
  @moduledoc "A staff person's support conversation with Palee (ADR-363)."

  use Ecto.Schema
  import Ecto.Changeset

  alias Palee.HelpDesk.Domain.ConversationPolicy

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "help_desk_conversations" do
    field :organization_id, :binary_id
    field :user_id, :binary_id
    field :status, :string, default: "assistant"
    field :locale, :string
    field :screen_path, :string
    field :subject, :string
    field :last_message_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(conversation, attrs) do
    conversation
    |> cast(attrs, [:user_id, :status, :locale, :screen_path, :subject, :last_message_at])
    |> validate_required([:user_id, :status, :locale, :subject, :last_message_at])
    |> validate_inclusion(:status, ConversationPolicy.statuses())
  end
end

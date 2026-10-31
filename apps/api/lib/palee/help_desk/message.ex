defmodule Palee.HelpDesk.Message do
  @moduledoc "One message of a support conversation (ADR-363). Insert-only."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "help_desk_messages" do
    field :organization_id, :binary_id
    field :conversation_id, :binary_id
    field :author, :string
    field :author_id, :binary_id
    field :body, :string
    field :citations, {:array, :map}, default: []
    field :guide_id, :string
    field :confident, :boolean

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(message, attrs) do
    message
    |> cast(attrs, [
      :conversation_id,
      :author,
      :author_id,
      :body,
      :citations,
      :guide_id,
      :confident,
      :inserted_at
    ])
    |> validate_required([:conversation_id, :author, :body])
    |> validate_inclusion(:author, ~w(person assistant palee))
    |> validate_length(:body, min: 1, max: 4000)
  end
end

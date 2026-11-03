defmodule Palee.Programmes.ProgrammeReview do
  @moduledoc "A buyer's review of a programme, one per purchase (ADR-370)."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  schema "programme_reviews" do
    field :organization_id, :binary_id, read_after_writes: true
    field :programme_id, :binary_id
    field :purchase_id, :binary_id
    field :user_id, :binary_id
    field :version_number, :integer
    field :rating, :integer
    field :body, :string
    field :status, :string, default: "published"
    field :hidden_reason, :string
    field :hidden_by_id, :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(review, attrs) do
    review
    |> cast(attrs, [
      :organization_id,
      :programme_id,
      :purchase_id,
      :user_id,
      :version_number,
      :rating,
      :body
    ])
    |> validate_required([:programme_id, :purchase_id, :user_id, :version_number, :rating])
    |> validate_number(:rating, greater_than_or_equal_to: 1, less_than_or_equal_to: 5)
    |> validate_length(:body, max: 1000)
    |> unique_constraint(:purchase_id)
  end

  def moderation_changeset(review, changes) do
    review
    |> cast(changes, [:status, :hidden_reason, :hidden_by_id])
    |> validate_inclusion(:status, ["published", "hidden"])
    |> check_constraint(:status, name: :programme_reviews_check)
  end
end

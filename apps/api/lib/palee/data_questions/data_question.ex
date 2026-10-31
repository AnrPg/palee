defmodule Palee.DataQuestions.DataQuestion do
  @moduledoc "One staff question over the box's data and its answer (ADR-361). Insert-only."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "data_questions" do
    field :organization_id, :binary_id
    field :user_id, :binary_id
    field :question, :string
    field :locale, :string
    field :status, :string
    field :error_code, :string
    field :answer, :string
    field :grounded, :boolean, default: false
    field :unsupported_numbers, {:array, :string}, default: []
    field :citations, {:array, :map}, default: []
    field :steps, {:array, :map}, default: []
    field :rounds, :integer, default: 0
    field :model, :string
    field :input_tokens, :integer, default: 0
    field :output_tokens, :integer, default: 0
    field :duration_ms, :integer

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @fields ~w(id user_id question locale status error_code answer grounded unsupported_numbers
             citations steps rounds model input_tokens output_tokens duration_ms inserted_at)a

  def changeset(organization_id, attrs) do
    %__MODULE__{organization_id: organization_id}
    |> cast(attrs, @fields)
    |> validate_required([:question, :locale, :status])
    |> validate_inclusion(:status, ~w(answered unanswerable failed refused))
    |> validate_length(:question, max: 500)
    |> validate_length(:answer, max: 4000)
  end
end

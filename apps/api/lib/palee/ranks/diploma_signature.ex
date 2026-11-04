defmodule Palee.Ranks.DiplomaSignature do
  @moduledoc """
  A coach's signature image for diplomas (ADR-377 addendum, option Γ),
  stored privately under the person's own prefix. One current row per
  person; a replaced one is retired and kept for the diplomas that point at
  it.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  schema "diploma_signatures" do
    field(:user_id, :binary_id)
    field(:object_key, :string)
    field(:content_type, :string)
    field(:byte_size, :integer)
    field(:width, :integer)
    field(:height, :integer)
    field(:sha256, :string)
    field(:retired_at, :utc_datetime_usec)

    timestamps(type: :utc_datetime_usec)
  end

  @fields ~w(user_id object_key content_type byte_size width height sha256)a

  def changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:id | @fields])
    |> validate_required(@fields)
    |> validate_inclusion(:content_type, ["image/png", "image/jpeg"])
    |> check_constraint(:content_type, name: :diploma_signatures_check)
    |> unique_constraint(:user_id, name: :diploma_signatures_current_index)
  end
end

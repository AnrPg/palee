defmodule Palee.Ranks.DiplomaSignatureEvent do
  @moduledoc "One audited change of a coach's diploma signature: `set` or `removed`. Insert-only."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  schema "diploma_signature_events" do
    field(:user_id, :binary_id)
    field(:action, :string)
    field(:signature_id, :binary_id)
    field(:sha256, :string)
    field(:occurred_at, :utc_datetime_usec)

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:user_id, :action, :signature_id, :sha256, :occurred_at])
    |> validate_required([:user_id, :action, :occurred_at])
    |> validate_inclusion(:action, ["set", "removed"])
  end
end

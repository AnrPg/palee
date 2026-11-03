defmodule Palee.Ranks.RankAward do
  @moduledoc """
  A promotion (or a stripe) a coach gave a person (ADR-377), with its
  diploma number. Withdrawn awards stay in the history with the reason.
  `signature_id` is the awarding coach's diploma signature current when the
  award was made (a snapshot reference, ADR-377 addendum).
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  schema "rank_awards" do
    field(:organization_id, :binary_id)
    field(:ladder_id, :binary_id)
    field(:rank_id, :binary_id)
    field(:user_id, :binary_id)
    field(:stripes, :integer, default: 0)
    field(:awarded_on, :date)
    field(:awarded_by_id, :binary_id)
    field(:note, :string)
    field(:skills_checked, {:array, :string}, default: [])
    field(:certificate_number, :string)
    field(:revoked_at, :utc_datetime_usec)
    field(:revoked_by_id, :binary_id)
    field(:revoke_reason, :string)
    field(:signature_id, :binary_id)

    timestamps(type: :utc_datetime_usec)
  end

  @fields ~w(organization_id ladder_id rank_id user_id stripes awarded_on awarded_by_id note
             skills_checked certificate_number signature_id)a

  def changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:id | @fields])
    |> validate_required([
      :organization_id,
      :ladder_id,
      :rank_id,
      :user_id,
      :awarded_on,
      :certificate_number
    ])
    |> validate_number(:stripes, greater_than_or_equal_to: 0, less_than_or_equal_to: 10)
    |> validate_length(:note, max: 500)
    |> validate_length(:skills_checked, max: 30)
    |> unique_constraint(:certificate_number,
      name: :rank_awards_organization_id_certificate_number_index
    )
    |> foreign_key_constraint(:rank_id, name: :rank_awards_rank_fkey)
    |> foreign_key_constraint(:ladder_id, name: :rank_awards_ladder_fkey)
  end

  def revoke_changeset(award, attrs) do
    award
    |> cast(attrs, [:revoked_at, :revoked_by_id, :revoke_reason])
    |> validate_required([:revoked_at, :revoke_reason])
    |> validate_length(:revoke_reason, min: 2, max: 280)
  end
end

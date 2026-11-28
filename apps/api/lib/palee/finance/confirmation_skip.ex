defmodule Palee.Finance.ConfirmationSkip do
  @moduledoc """
  ADR-795: one «Να μην εμφανιστεί ξανά σήμερα»: who, which question, which
  box day. Kept as the record of the choice.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "finance_confirmation_skips" do
    field :organization_id, :binary_id, read_after_writes: true
    field :user_id, :binary_id
    field :kind, :string
    field :skip_on, :date

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(skip \\ %__MODULE__{}, params) do
    skip
    |> cast(params, [:kind, :skip_on])
    |> validate_required([:kind, :skip_on])
    |> validate_inclusion(:kind, Palee.Finance.Domain.MoneyConfirmations.kinds())
    |> unique_constraint([:organization_id, :user_id, :kind, :skip_on])
  end
end

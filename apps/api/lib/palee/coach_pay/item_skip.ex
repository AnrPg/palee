defmodule Palee.CoachPay.ItemSkip do
  @moduledoc """
  ADR-510: a recurring allowance taken off one person for one period. The
  calculation leaves it out until it is put back.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "coach_pay_item_skips" do
    field :organization_id, :binary_id, read_after_writes: true
    field :period_id, :binary_id
    field :pay_item_id, :binary_id
    field :user_id, :binary_id
    field :created_by_id, :binary_id

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(skip, attrs) do
    skip
    |> cast(attrs, [:period_id, :pay_item_id, :user_id, :created_by_id])
    |> validate_required([:period_id, :pay_item_id, :user_id])
    |> unique_constraint([:period_id, :user_id, :pay_item_id])
  end
end

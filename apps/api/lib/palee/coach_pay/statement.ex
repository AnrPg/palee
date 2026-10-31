defmodule Palee.CoachPay.Statement do
  @moduledoc "ADR-341: one coach's pay for one period."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "coach_pay_statements" do
    field :organization_id, :binary_id, read_after_writes: true
    field :period_id, :binary_id
    field :coach_user_id, :binary_id
    field :total_cents, :integer, default: 0
    field :line_count, :integer, default: 0

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(statement, attrs) do
    statement
    |> cast(attrs, [:period_id, :coach_user_id, :total_cents, :line_count])
    |> validate_required([:period_id, :coach_user_id])
    |> unique_constraint([:period_id, :coach_user_id])
  end
end

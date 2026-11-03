defmodule Palee.Retention.Risk do
  @moduledoc "ADR-347: a box member's latest risk score, its reasons and what staff did about it."

  use Ecto.Schema
  import Ecto.Changeset

  alias Palee.Retention.Domain.RiskScore

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  schema "retention_risks" do
    field :organization_id, :binary_id, read_after_writes: true
    field :user_id, :binary_id
    field :score, :integer
    field :level, :string
    field :reasons, {:array, :map}, default: []
    field :suggested_action, :string
    field :computed_at, :utc_datetime_usec
    field :level_since, :utc_datetime_usec
    field :snoozed_until, :date
    field :contacted_at, :utc_datetime_usec
    field :contacted_by_id, :binary_id
    field :win_back_queued_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(risk, params) do
    risk
    |> cast(params, [
      :user_id,
      :score,
      :level,
      :reasons,
      :suggested_action,
      :computed_at,
      :level_since,
      :snoozed_until,
      :contacted_at,
      :contacted_by_id,
      :win_back_queued_at
    ])
    |> validate_required([:user_id, :score, :level, :computed_at, :level_since])
    |> validate_inclusion(:level, RiskScore.levels())
    |> validate_number(:score, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> unique_constraint([:organization_id, :user_id])
  end
end

defmodule Palee.CoachPay.Period do
  @moduledoc "ADR-341: a pay period (gym-local dates) and where it stands."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  @fields ~w(starts_on ends_on status currency total_cents gross_cents net_cents calculated_at approved_at
             approved_by_id exported_at reopen_reason created_by_id)a

  schema "coach_pay_periods" do
    field :organization_id, :binary_id, read_after_writes: true
    field :starts_on, :date
    field :ends_on, :date
    field :status, :string, default: "draft"
    field :currency, :string
    field :total_cents, :integer, default: 0
    field :gross_cents, :integer, default: 0
    field :net_cents, :integer, default: 0
    field :calculated_at, :utc_datetime_usec
    field :approved_at, :utc_datetime_usec
    field :approved_by_id, :binary_id
    field :exported_at, :utc_datetime_usec
    field :reopen_reason, :string
    field :created_by_id, :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(period, attrs) do
    period
    |> cast(attrs, @fields)
    |> validate_required([:starts_on, :ends_on, :status, :currency])
    |> unique_constraint([:organization_id, :starts_on],
      name: :coach_pay_periods_organization_id_starts_on_index,
      message: "overlaps"
    )
    |> check_constraint(:status, name: :coach_pay_periods_status_check)
    |> check_constraint(:ends_on, name: :coach_pay_periods_dates_check)
  end
end

defmodule Palee.CoachPay.Rule do
  @moduledoc "ADR-341: how one coach is paid, from a date (and until one)."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  @fields ~w(coach_user_id kind amount_cents percent_bps currency class_type_ids count_statuses
             min_attendees max_attendees sales_scope starts_on ends_on note archived_at
             created_by_id)a

  schema "coach_pay_rules" do
    field :organization_id, :binary_id, read_after_writes: true
    field :coach_user_id, :binary_id
    field :kind, :string
    field :amount_cents, :integer
    field :percent_bps, :integer
    field :currency, :string
    field :class_type_ids, {:array, :binary_id}, default: []
    field :count_statuses, {:array, :string}, default: ["attended"]
    field :min_attendees, :integer, default: 0
    field :max_attendees, :integer
    field :sales_scope, :string
    field :starts_on, :date
    field :ends_on, :date
    field :note, :string
    field :archived_at, :utc_datetime_usec
    field :created_by_id, :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(rule, attrs) do
    rule
    |> cast(attrs, @fields)
    |> validate_required([:coach_user_id, :kind, :currency, :starts_on])
    |> check_constraint(:kind, name: :coach_pay_rules_kind_check)
    |> check_constraint(:amount_cents, name: :coach_pay_rules_amount_check)
    |> check_constraint(:ends_on, name: :coach_pay_rules_dates_check)
    |> foreign_key_constraint(:coach_user_id)
  end
end

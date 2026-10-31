defmodule Palee.CoachPay.Line do
  @moduledoc """
  ADR-341: one line of a coach's statement, naming what it comes from
  (a class, a session, a payment or refund, or a staff adjustment).
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  @fields ~w(statement_id rule_id kind source_type source_id occurred_on description quantity
             unit_cents base_cents percent_bps amount_cents created_by_id)a

  schema "coach_pay_lines" do
    field :organization_id, :binary_id, read_after_writes: true
    field :statement_id, :binary_id
    field :rule_id, :binary_id
    field :kind, :string
    field :source_type, :string
    field :source_id, :binary_id
    field :occurred_on, :date
    field :description, :string
    field :quantity, :integer, default: 1
    field :unit_cents, :integer
    field :base_cents, :integer
    field :percent_bps, :integer
    field :amount_cents, :integer
    field :created_by_id, :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(line, attrs) do
    line
    |> cast(attrs, @fields)
    |> validate_required([:statement_id, :kind, :source_type, :occurred_on, :description])
    |> validate_required([:amount_cents])
    |> check_constraint(:kind, name: :coach_pay_lines_kind_check)
    |> check_constraint(:source_type, name: :coach_pay_lines_source_check)
  end
end

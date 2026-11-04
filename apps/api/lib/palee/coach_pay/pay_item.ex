defmodule Palee.CoachPay.PayItem do
  @moduledoc """
  ADR-382: one entry of the box's catalogue of overtime and allowances:
  what it pays, per what, to which roles, whether gross or net and, for
  overtime, above how many hours a week.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  @fields ~w(kind name amount_cents unit roles weekly_threshold frequency currency amount_basis archived_at
             created_by_id)a

  schema "coach_pay_items" do
    field :organization_id, :binary_id, read_after_writes: true
    field :kind, :string
    field :name, :string
    field :amount_cents, :integer
    field :unit, :string
    field :roles, {:array, :string}, default: []
    field :weekly_threshold, :integer
    field :frequency, :string
    field :currency, :string
    field :amount_basis, :string, default: "gross"
    field :archived_at, :utc_datetime_usec
    field :created_by_id, :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(item, attrs) do
    item
    |> cast(attrs, @fields)
    |> validate_required([:kind, :name, :amount_cents, :unit, :roles, :currency])
    |> check_constraint(:unit, name: :coach_pay_items_unit_check)
    |> check_constraint(:amount_cents, name: :coach_pay_items_amount_check)
    |> check_constraint(:weekly_threshold, name: :coach_pay_items_threshold_check)
    |> check_constraint(:frequency, name: :coach_pay_items_frequency_check)
    |> check_constraint(:roles, name: :coach_pay_items_roles_check)
    |> check_constraint(:amount_basis, name: :coach_pay_items_basis_check)
  end
end

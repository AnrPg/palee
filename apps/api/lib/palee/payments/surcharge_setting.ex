defmodule Palee.Payments.SurchargeSetting do
  @moduledoc "ADR-340: the box's choice to pass the card fee on to the person paying."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  @fields ~w(enabled channels percent_bps fixed_cents region_code at_cost_confirmed
             updated_by_id)a

  schema "payment_surcharge_settings" do
    field :organization_id, :binary_id, read_after_writes: true
    field :enabled, :boolean, default: false
    field :channels, {:array, :string}, default: []
    field :percent_bps, :integer, default: 0
    field :fixed_cents, :integer, default: 0
    field :region_code, :string
    field :at_cost_confirmed, :boolean, default: false
    field :updated_by_id, :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(setting, attrs) do
    setting
    |> cast(attrs, @fields)
    |> validate_number(:percent_bps, greater_than_or_equal_to: 0, less_than_or_equal_to: 1_000)
    |> validate_number(:fixed_cents, greater_than_or_equal_to: 0, less_than_or_equal_to: 10_000)
    |> unique_constraint(:organization_id)
    |> check_constraint(:channels, name: :payment_surcharge_settings_channels_check)
  end
end

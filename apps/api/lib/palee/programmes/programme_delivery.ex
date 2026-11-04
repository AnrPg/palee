defmodule Palee.Programmes.ProgrammeDelivery do
  @moduledoc "One WOD a purchase scheduled for its buyer (an assigned workout), ADR-371."

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "programme_deliveries" do
    field :organization_id, :binary_id, read_after_writes: true
    field :purchase_id, :binary_id
    field :user_id, :binary_id
    field :assigned_workout_id, :binary_id
    field :day, :integer
    field :scheduled_for, :date

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end

defmodule Palee.Finance.PackageWaitBooking do
  @moduledoc """
  ADR-717: a class booked while the person's «Το θέλω» waited for the front
  desk. The box's `package_wait_bookings` says how many a person may make;
  the rows count them per person and box, for good.
  """

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "finance_package_wait_bookings" do
    field :organization_id, :binary_id, read_after_writes: true
    field :user_id, :binary_id
    field :package_request_id, :binary_id
    field :scheduled_class_id, :binary_id
    field :booked_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end

defmodule Palee.Finance.PackageRemoval do
  @moduledoc """
  ADR-660: one «Αφαίρεση πακέτου»: who removed which package, why, what
  happened to an unpaid invoice nobody paid anything on, and whether the
  removal was undone or settled (upcoming bookings cancelled, member told).
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "finance_package_removals" do
    field :organization_id, :binary_id, read_after_writes: true
    field :membership_id, :binary_id
    field :subscription_id, :binary_id
    field :user_id, :binary_id
    field :package_name, :string
    field :previous_status, :string
    field :removed_on, :date
    field :actor_id, :binary_id
    field :actor_roles, {:array, :string}, default: []
    field :reason, :string
    field :reason_shared, :boolean, default: false
    field :invoice_choice, :string
    field :voided_invoices, {:array, :map}, default: []
    field :previous_leaving_on, :date
    field :previous_expires_on, :date
    field :leaving_changed, :boolean, default: false
    field :undo_until, :utc_datetime_usec
    field :undone_at, :utc_datetime_usec
    field :undone_by_id, :binary_id
    field :settled_at, :utc_datetime_usec
    field :cancelled_bookings, :integer

    timestamps(type: :utc_datetime_usec)
  end

  @insert_fields [
    :membership_id,
    :subscription_id,
    :user_id,
    :package_name,
    :previous_status,
    :removed_on,
    :actor_id,
    :actor_roles,
    :reason,
    :reason_shared,
    :invoice_choice,
    :voided_invoices,
    :previous_leaving_on,
    :previous_expires_on,
    :leaving_changed,
    :undo_until
  ]

  @doc "A new removal."
  def changeset(params) do
    %__MODULE__{}
    |> cast(params, @insert_fields)
    |> validate_required([
      :membership_id,
      :subscription_id,
      :user_id,
      :package_name,
      :previous_status,
      :removed_on,
      :actor_id,
      :undo_until
    ])
    |> validate_inclusion(:invoice_choice, ["void", "keep"])
    |> validate_length(:reason, max: 500)
    |> unique_constraint(:subscription_id, name: :finance_package_removals_one_open_index)
    |> check_constraint(:invoice_choice, name: :finance_package_removals_choice_check)
  end

  @doc "Staff undid the removal in time."
  def undo_changeset(%__MODULE__{} = removal, %DateTime{} = now, actor_id) do
    removal
    |> change(undone_at: now, undone_by_id: actor_id)
    |> check_constraint(:undone_at, name: :finance_package_removals_outcome_check)
  end

  @doc "The undo closed: the removal stands; `cancelled_bookings` is set once they are cancelled."
  def settle_changeset(%__MODULE__{} = removal, attrs) do
    removal
    |> cast(attrs, [:settled_at, :cancelled_bookings])
    |> validate_number(:cancelled_bookings, greater_than_or_equal_to: 0)
    |> check_constraint(:settled_at, name: :finance_package_removals_outcome_check)
  end
end

defmodule Palee.Finance.PackageRequest do
  @moduledoc "ADR-291: a package waiting to be paid at the front desk («Περιμένει πληρωμή»)."

  use Ecto.Schema
  import Ecto.Changeset

  alias Palee.Finance.Domain.PackageRequestPolicy

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "finance_package_requests" do
    field :organization_id, :binary_id, read_after_writes: true
    field :user_id, :binary_id
    field :membership_package_id, :binary_id
    field :package_name_snapshot, :string
    field :price_cents_snapshot, :integer
    field :currency, :string
    field :status, :string, default: "pending"
    field :source, :string, default: "member"
    field :requested_by_id, :binary_id
    field :hold_until, :date
    field :closed_at, :utc_datetime_usec
    field :closed_by_id, :binary_id
    field :membership_package_subscription_id, :binary_id
    field :membership_payment_id, :binary_id
    # ADR-633: the one class booked while the first request waited.
    field :first_class_at, :utc_datetime_usec
    field :first_class_scheduled_class_id, :binary_id
    field :decline_reason, :string

    timestamps(type: :utc_datetime_usec)
  end

  def create_changeset(params) do
    %__MODULE__{}
    |> cast(params, [
      :user_id,
      :membership_package_id,
      :package_name_snapshot,
      :price_cents_snapshot,
      :currency,
      :source,
      :requested_by_id,
      :hold_until
    ])
    |> validate_required([
      :user_id,
      :membership_package_id,
      :package_name_snapshot,
      :price_cents_snapshot,
      :currency,
      :source,
      :hold_until
    ])
    |> validate_inclusion(:source, PackageRequestPolicy.sources())
    |> validate_number(:price_cents_snapshot, greater_than: 0)
    |> unique_constraint([:organization_id, :user_id, :membership_package_id],
      name: :finance_package_requests_one_pending_index
    )
  end

  def close_changeset(request, params) do
    request
    |> cast(params, [
      :status,
      :closed_at,
      :closed_by_id,
      :membership_package_subscription_id,
      :membership_payment_id,
      :decline_reason
    ])
    |> validate_required([:status, :closed_at])
    |> validate_decline_reason()
    |> validate_inclusion(:status, PackageRequestPolicy.statuses() -- ["pending"])
  end

  defp validate_decline_reason(changeset) do
    if get_field(changeset, :status) == "declined" do
      changeset
      |> update_change(:decline_reason, &String.trim/1)
      |> validate_required([:decline_reason])
      |> validate_length(:decline_reason, max: 500)
    else
      changeset
    end
  end
end

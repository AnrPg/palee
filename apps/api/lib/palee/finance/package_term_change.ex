defmodule Palee.Finance.PackageTermChange do
  @moduledoc """
  ADR-770: one saved change of a subscription package that had holders:
  what changed, whom it was for (`active`: the holders too, `new_only`:
  new purchases only), the subscriptions staff left out and who saved it.
  """

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "finance_package_term_changes" do
    field :organization_id, :binary_id, read_after_writes: true
    field :membership_package_id, :binary_id
    field :changed_by, :binary_id
    field :apply_to, :string
    field :price_before_cents, :integer
    field :price_after_cents, :integer
    field :fields_before, :map, default: %{}
    field :fields_after, :map, default: %{}
    field :excluded_subscription_ids, {:array, :binary_id}, default: []
    field :holders_count, :integer, default: 0

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end

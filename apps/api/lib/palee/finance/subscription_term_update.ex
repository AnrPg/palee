defmodule Palee.Finance.SubscriptionTermUpdate do
  @moduledoc """
  ADR-770: the terms a package change gives one subscription, `now`
  (applied when saved) or from its `next_period` (`pending` until
  `effective_on`, then `applied`; `superseded` when a later change merged
  into a newer pending row). `price_cents` nil: the price stays.
  """

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "finance_subscription_term_updates" do
    field :organization_id, :binary_id, read_after_writes: true
    field :subscription_id, :binary_id
    field :membership_id, :binary_id
    field :user_id, :binary_id
    field :term_change_id, :binary_id
    field :timing, :string
    field :status, :string
    field :effective_on, :date
    field :price_cents, :integer
    field :fields, :map, default: %{}
    field :changes, {:array, :map}, default: []
    field :applied_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end
end

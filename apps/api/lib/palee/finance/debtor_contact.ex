defmodule Palee.Finance.DebtorContact do
  @moduledoc """
  ADR-396: the name, email and SMS number a profile had when it was deleted while it
  still owed this box money. The box keeps them only to claim that debt
  (GDPR art. 17(3)(e)) and they go as soon as the person owes it nothing.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "finance_debtor_contacts" do
    field :organization_id, :binary_id
    field :membership_id, :binary_id
    field :user_id, :binary_id
    field :display_name, :string
    field :email, :string
    field :phone_e164, :string
    field :locale, :string, default: "en"
    field :kept_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  @fields [
    :organization_id,
    :membership_id,
    :user_id,
    :display_name,
    :email,
    :phone_e164,
    :locale,
    :kept_at
  ]

  def changeset(contact \\ %__MODULE__{}, params) do
    contact
    |> cast(params, @fields)
    |> validate_required(@fields -- [:email, :phone_e164, :locale])
    |> unique_constraint([:organization_id, :membership_id])
  end
end

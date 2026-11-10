defmodule Palee.Finance.MemberBenefit do
  @moduledoc """
  ADR-612: one row of the member benefits ledger, a grant («Δώρο ή χάρη») or
  the revocation of one. Insert-only: the database refuses an update.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Palee.Finance.Domain.MemberBenefits

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "finance_member_benefits" do
    field :organization_id, :binary_id, read_after_writes: true
    field :membership_id, :binary_id
    field :user_id, :binary_id
    field :action, :string
    field :kind, :string
    field :benefit_id, :binary_id
    field :starts_on, :date
    field :ends_on, :date
    field :amount_cents, :integer
    field :details, :map, default: %{}
    field :reason, :string
    field :actor_id, :binary_id
    field :actor_roles, {:array, :string}, default: []
    field :request_id, :string
    field :idempotency_key, :string

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @fields [
    :membership_id,
    :user_id,
    :action,
    :kind,
    :benefit_id,
    :starts_on,
    :ends_on,
    :amount_cents,
    :details,
    :reason,
    :actor_id,
    :actor_roles,
    :request_id,
    :idempotency_key
  ]

  @doc "A new row; `id` may be given, so what it touched can name it first."
  def changeset(params) do
    %__MODULE__{id: Map.get(params, :id) || Map.get(params, "id")}
    |> cast(params, @fields)
    |> validate_required([:membership_id, :user_id, :action, :kind, :actor_id, :idempotency_key])
    |> validate_inclusion(:action, ["grant", "revoke"])
    |> validate_inclusion(:kind, MemberBenefits.kinds())
    |> validate_length(:reason, max: 500)
    |> validate_number(:amount_cents, greater_than_or_equal_to: 0)
    |> unique_constraint([:organization_id, :idempotency_key])
    |> unique_constraint(:benefit_id, name: :finance_member_benefits_one_revocation_index)
    |> check_constraint(:ends_on, name: :finance_member_benefits_access_dates_check)
  end
end

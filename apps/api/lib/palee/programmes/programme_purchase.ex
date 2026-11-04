defmodule Palee.Programmes.ProgrammePurchase do
  @moduledoc """
  One buyer's purchase of one programme version (ADR-371). The price, the
  refund rule and the withdrawal record are copied at purchase, so later
  changes to the programme never reach it.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Palee.Programmes.Domain.PurchaseLifecycle

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  schema "programme_purchases" do
    field :organization_id, :binary_id, read_after_writes: true
    field :programme_id, :binary_id
    field :version_id, :binary_id
    field :user_id, :binary_id
    field :status, :string, default: "pending_payment"
    field :price_cents, :integer
    field :currency, :string
    field :refund_policy, :string
    field :starts_on, :date
    field :ends_on, :date
    field :payment_intent_id, :binary_id
    field :finance_payment_id, :binary_id
    field :fiscal_document_id, :binary_id
    field :withdrawal, :map, default: %{}
    field :refunded_cents, :integer, default: 0
    field :idempotency_key, :string
    field :activated_at, :utc_datetime_usec
    field :ended_at, :utc_datetime_usec
    field :end_reason, :string
    # ADR-540: the days the buyer moved or skipped, and the end sold with.
    field :day_dates, :map, default: %{}
    field :skipped_days, {:array, :integer}, default: []
    field :planned_ends_on, :date

    timestamps(type: :utc_datetime_usec)
  end

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [
      :organization_id,
      :programme_id,
      :version_id,
      :user_id,
      :price_cents,
      :currency,
      :refund_policy,
      :starts_on,
      :ends_on,
      :withdrawal,
      :idempotency_key
    ])
    |> validate_required([
      :programme_id,
      :version_id,
      :user_id,
      :price_cents,
      :currency,
      :refund_policy,
      :starts_on,
      :ends_on,
      :idempotency_key
    ])
    |> then(&put_change(&1, :planned_ends_on, get_field(&1, :ends_on)))
    |> unique_constraint([:organization_id, :idempotency_key])
    |> check_constraint(:status, name: :programme_purchases_check)
  end

  @doc "ADR-540: the buyer's moves and skips, as `PurchaseSchedule` decided them."
  def schedule_changeset(purchase, changes) do
    purchase
    |> cast(changes, [:day_dates, :skipped_days, :ends_on, :planned_ends_on])
    |> check_constraint(:ends_on, name: :programme_purchases_days_check)
    |> check_constraint(:status, name: :programme_purchases_check)
  end

  def payment_changeset(purchase, intent_id),
    do: purchase |> change(payment_intent_id: intent_id) |> unique_constraint(:payment_intent_id)

  def transition_changeset(purchase, changes) do
    purchase
    |> cast(changes, [
      :status,
      :activated_at,
      :finance_payment_id,
      :fiscal_document_id,
      :refunded_cents,
      :ended_at,
      :end_reason
    ])
    |> validate_inclusion(:status, PurchaseLifecycle.statuses())
    |> check_constraint(:status, name: :programme_purchases_check)
  end
end

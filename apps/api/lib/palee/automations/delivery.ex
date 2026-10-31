defmodule Palee.Automations.Delivery do
  @moduledoc """
  ADR-346: one automatic message in the outbox: which recipe, to whom (a
  profile or a lead), when it is due, and what became of it.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Palee.Automations.Domain.DeliveryPolicy

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  schema "automation_deliveries" do
    field :organization_id, :binary_id, read_after_writes: true
    field :recipe, :string
    field :user_id, :binary_id
    field :lead_id, :binary_id
    field :trigger_ref, :string
    field :data, :map, default: %{}
    field :due_at, :utc_datetime_usec
    field :status, :string, default: "pending"
    field :channel, :string
    field :attempts, :integer, default: 0
    field :claimed_at, :utc_datetime_usec
    field :sent_at, :utc_datetime_usec
    field :skip_reason, :string
    field :last_error, :string
    field :external_ref, :string

    timestamps(type: :utc_datetime_usec)
  end

  def create_changeset(params) do
    %__MODULE__{}
    |> cast(params, [:recipe, :user_id, :lead_id, :trigger_ref, :data, :due_at])
    |> validate_required([:recipe, :trigger_ref, :due_at])
    |> check_constraint(:user_id, name: :automation_deliveries_recipient_check)
    |> unique_constraint([:organization_id, :recipe, :trigger_ref],
      name: :automation_deliveries_trigger_index
    )
  end

  def finish_changeset(delivery, params) do
    delivery
    |> cast(params, [
      :status,
      :channel,
      :due_at,
      :claimed_at,
      :sent_at,
      :skip_reason,
      :last_error,
      :external_ref
    ])
    |> validate_inclusion(:status, DeliveryPolicy.statuses())
    |> validate_length(:last_error, max: 255)
  end
end

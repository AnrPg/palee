defmodule Palee.Retention.RiskAction do
  @moduledoc """
  ADR-384: one thing staff did about a box member «Σε κίνδυνο»: who, when,
  and what («Επικοινώνησα» with its channel, «Αργότερα» with the date the
  member comes back to the list, or showing them again).
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @kinds ~w(contacted snoozed unsnoozed)

  @type t :: %__MODULE__{}

  schema "retention_risk_actions" do
    field :organization_id, :binary_id, read_after_writes: true
    field :user_id, :binary_id
    field :actor_id, :binary_id
    field :kind, :string
    field :channel, :string
    field :snoozed_until, :date
    field :at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def kinds, do: @kinds

  def changeset(action, params) do
    action
    |> cast(params, [:user_id, :actor_id, :kind, :channel, :snoozed_until, :at])
    |> validate_required([:user_id, :kind, :at])
    |> validate_inclusion(:kind, @kinds)
  end
end

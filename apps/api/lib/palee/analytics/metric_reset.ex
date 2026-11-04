defmodule Palee.Analytics.MetricReset do
  @moduledoc """
  ADR-462 §4/§5: a per-metric baseline. `scope` `organization` is a box's
  (set by its owner or an admin, `organization_id`); `member` is a person's
  own Πρόοδος (`user_id`, account-level). Undoing keeps the row
  (`undone_at`, `undone_by`) so the history stays complete.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "analytics_metric_resets" do
    field :scope, :string
    field :organization_id, :binary_id
    field :user_id, :binary_id
    field :metric_key, :string
    field :reset_at, :utc_datetime_usec
    field :reset_by, :binary_id
    field :undone_at, :utc_datetime_usec
    field :undone_by, :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(reset \\ %__MODULE__{}, params) do
    reset
    |> cast(params, [:scope, :organization_id, :user_id, :metric_key, :reset_at, :reset_by])
    |> validate_required([:scope, :metric_key, :reset_at])
    |> validate_inclusion(:scope, ["organization", "member"])
    |> validate_length(:metric_key, max: 80)
    |> check_constraint(:scope, name: :analytics_metric_resets_scope_check)
  end
end

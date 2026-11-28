defmodule Palee.Finance.PackageStart do
  @moduledoc """
  ADR-795: the start of one package that waited for the member's first class
  or WOD. `waiting` until that session, then `started`, or `review` while the
  member has not yet seen what changed in the package meanwhile
  (`acknowledged_at` / `acknowledged_by_id` say who pressed «Το κατάλαβα»).
  A package removed meanwhile (ADR-660) keeps its row and neither waits nor
  starts while removed (an undone removal lets it wait again).
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ~w(waiting review started)
  @session_kinds ~w(class workout)
  @severities ~w(important serious warning)

  schema "finance_package_starts" do
    field :organization_id, :binary_id, read_after_writes: true
    field :subscription_id, :binary_id
    field :membership_id, :binary_id
    field :user_id, :binary_id
    field :package_name, :string
    field :waiting_since, :date
    field :status, :string, default: "waiting"
    field :session_kind, :string
    field :session_id, :binary_id
    field :session_on, :date
    field :severity, :string
    field :changes, {:array, :map}, default: []
    field :started_on, :date
    field :reviewed_at, :utc_datetime_usec
    field :acknowledged_at, :utc_datetime_usec
    field :acknowledged_by_id, :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  def statuses, do: @statuses

  def changeset(start \\ %__MODULE__{}, params) do
    start
    |> cast(params, [
      :subscription_id,
      :membership_id,
      :user_id,
      :package_name,
      :waiting_since,
      :status,
      :session_kind,
      :session_id,
      :session_on,
      :severity,
      :changes,
      :started_on,
      :reviewed_at,
      :acknowledged_at,
      :acknowledged_by_id
    ])
    |> validate_required([
      :subscription_id,
      :membership_id,
      :user_id,
      :package_name,
      :waiting_since,
      :status
    ])
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:session_kind, @session_kinds)
    |> validate_inclusion(:severity, @severities)
    |> unique_constraint(:subscription_id)
    |> check_constraint(:status, name: :finance_package_starts_status_check)
  end
end

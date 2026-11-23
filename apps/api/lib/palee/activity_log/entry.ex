defmodule Palee.ActivityLog.Entry do
  @moduledoc """
  ADR-760: one row of the box's «Αρχείο ενεργειών». Insert-only: the
  database refuses an update, except forgetting a person (9A).
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Palee.ActivityLog.Domain.Actions

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "activity_log_entries" do
    field :organization_id, :binary_id, read_after_writes: true
    field :occurred_at, :utc_datetime_usec
    field :action, :string
    field :area, :string
    field :actor_user_id, :binary_id
    field :actor_roles, {:array, :string}, default: []
    field :person_user_id, :binary_id
    field :subject, :map, default: %{}
    field :subject_label, :string
    field :details, :map, default: %{}
    field :reason, :string
    field :reason_shared, :boolean, default: false
    field :sensitive, :boolean, default: false
    field :request_id, :string
    field :source, :string, default: "request"
    field :source_ref, :string
    field :redacted_at, :utc_datetime_usec
  end

  @fields [
    :occurred_at,
    :action,
    :actor_user_id,
    :actor_roles,
    :person_user_id,
    :subject,
    :subject_label,
    :details,
    :reason,
    :reason_shared,
    :request_id,
    :source,
    :source_ref
  ]

  @max_reason 1000

  def max_reason, do: @max_reason

  @doc "A new row. The area and `sensitive` come from the action key."
  def changeset(params) do
    %__MODULE__{}
    |> cast(params, @fields)
    |> put_default_time()
    |> validate_required([:action])
    |> validate_change(:action, fn :action, key ->
      if Actions.known?(key), do: [], else: [action: "is not a known action"]
    end)
    |> put_area()
    |> validate_inclusion(:source, ["request", "backfill", "system"])
    |> validate_length(:reason, max: @max_reason)
    |> validate_length(:subject_label, max: 300)
    |> check_constraint(:actor_user_id, name: :activity_log_entries_actor_check)
    |> unique_constraint([:organization_id, :source_ref],
      name: :activity_log_entries_source_ref_index
    )
  end

  defp put_default_time(changeset) do
    case get_field(changeset, :occurred_at) do
      nil -> put_change(changeset, :occurred_at, DateTime.utc_now())
      _at -> changeset
    end
  end

  defp put_area(changeset) do
    case get_field(changeset, :action) do
      key when is_binary(key) ->
        if Actions.known?(key) do
          changeset
          |> put_change(:area, Atom.to_string(Actions.area(key)))
          |> put_change(:sensitive, Actions.sensitive?(key))
        else
          changeset
        end

      _none ->
        changeset
    end
  end
end

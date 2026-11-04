defmodule Palee.Workouts.ExerciseCatalogAuditEvent do
  @moduledoc "ADR-461: one decision of the Palee team on the exercise catalog (append-only)."

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "exercise_catalog_audit_events" do
    field :action, :string
    field :actor_user_id, :binary_id
    field :candidate_id, :binary_id
    field :catalog_slug, :string
    field :metadata, :map, default: %{}

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end

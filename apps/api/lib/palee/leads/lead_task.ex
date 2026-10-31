defmodule Palee.Leads.LeadTask do
  @moduledoc "ADR-344: something to do about a lead by a date («Επόμενη ενέργεια»)."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  schema "lead_tasks" do
    field :organization_id, :binary_id, read_after_writes: true
    field :lead_id, :binary_id
    field :title, :string
    field :due_at, :utc_datetime_usec
    field :assignee_id, :binary_id
    field :done_at, :utc_datetime_usec
    field :done_by_id, :binary_id
    field :created_by_id, :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  def create_changeset(params) do
    %__MODULE__{}
    |> cast(params, [:lead_id, :title, :due_at, :assignee_id, :created_by_id])
    |> validate_required([:lead_id, :title, :due_at])
    |> validate_length(:title, min: 1, max: 160)
  end

  def done_changeset(task, params) do
    task
    |> cast(params, [:done_at, :done_by_id])
    |> validate_required([:done_at])
  end
end

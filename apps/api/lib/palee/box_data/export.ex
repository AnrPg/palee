defmodule Palee.BoxData.Export do
  @moduledoc """
  ADR-365: one owner's request for a copy of the box's data. Built in the
  background, stored under the tenant prefix (`file`: name, key, bytes,
  sha256), offered until `expires_at`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Palee.BoxData.Domain.ExportPolicy

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  schema "box_data_exports" do
    field :organization_id, :binary_id
    field :requested_by_id, :binary_id
    field :status, :string, default: "pending"
    field :record_count, :integer
    field :table_count, :integer
    field :file, :map
    # ADR-367: the ZIP parts with the box's stored files (photos, PDFs).
    field :parts, {:array, :map}, default: []
    field :error, :string
    field :requested_at, :utc_datetime_usec
    field :completed_at, :utc_datetime_usec
    field :expires_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:organization_id, :requested_by_id, :requested_at])
    |> validate_required([:organization_id, :requested_at])
    |> unique_constraint(:organization_id, name: :box_data_exports_one_pending_index)
  end

  def finish_changeset(export, attrs) do
    export
    |> cast(attrs, [
      :status,
      :record_count,
      :table_count,
      :file,
      :parts,
      :error,
      :completed_at,
      :expires_at
    ])
    |> validate_inclusion(:status, ExportPolicy.statuses())
    |> validate_length(:error, max: 500)
  end
end

defmodule Palee.ReviewAsks.ReviewAskSettings do
  @moduledoc "A box's Google review ask settings (ADR-355)."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "review_ask_settings" do
    field :organization_id, :binary_id, read_after_writes: true
    field :google_place_id, :string
    field :enabled, :boolean, default: false
    field :milestones, {:array, :integer}, default: [10, 50, 100]
    field :lock_version, :integer, default: 1
    field :updated_by_id, :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(settings, attrs) do
    settings
    |> cast(attrs, [:google_place_id, :enabled, :milestones, :updated_by_id])
    |> then(&if(&1.data.__meta__.state == :loaded, do: optimistic_lock(&1, :lock_version), else: &1))
    |> check_constraint(:google_place_id, name: :review_ask_settings_check)
    |> unique_constraint(:organization_id)
  end
end

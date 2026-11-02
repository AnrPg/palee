defmodule Palee.ReviewAsks.GooglePlaceSnapshot do
  @moduledoc "The box's Google rating and up to five reviews, refreshed daily (ADR-387)."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  @fields ~w(place_id name rating rating_count maps_uri reviews status fetched_at
             next_refresh_at attempts)a

  schema "google_place_snapshots" do
    field :organization_id, :binary_id, read_after_writes: true
    field :place_id, :string
    field :name, :string
    field :rating, :decimal
    field :rating_count, :integer
    field :maps_uri, :string
    field :reviews, {:array, :map}, default: []
    field :status, :string, default: "ok"
    field :fetched_at, :utc_datetime_usec
    field :next_refresh_at, :utc_datetime_usec
    field :attempts, :integer, default: 0

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(snapshot, attrs) do
    snapshot
    |> cast(attrs, @fields)
    |> validate_required([:place_id, :fetched_at, :next_refresh_at])
    |> check_constraint(:rating, name: :google_place_snapshots_check)
    |> unique_constraint(:organization_id)
  end
end

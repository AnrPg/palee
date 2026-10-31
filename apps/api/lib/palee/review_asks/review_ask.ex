defmodule Palee.ReviewAsks.ReviewAsk do
  @moduledoc "One review ask shown to a member and what they did (ADR-355)."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "review_asks" do
    field :organization_id, :binary_id, read_after_writes: true
    field :user_id, :binary_id
    field :trigger, :string, default: "attendance_milestone"
    field :milestone, :integer
    field :status, :string, default: "shown"
    field :shown_at, :utc_datetime_usec
    field :responded_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(ask, attrs) do
    ask
    |> cast(attrs, [:user_id, :trigger, :milestone, :status, :shown_at, :responded_at])
    |> validate_required([:user_id, :trigger, :milestone, :status, :shown_at])
    |> unique_constraint([:organization_id, :user_id, :trigger, :milestone])
    |> check_constraint(:status, name: :review_asks_check)
  end
end

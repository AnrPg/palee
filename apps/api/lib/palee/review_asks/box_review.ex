defmodule Palee.ReviewAsks.BoxReview do
  @moduledoc "An in-app review of a box by a person who checked in there (ADR-386)."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "box_reviews" do
    field :organization_id, :binary_id, read_after_writes: true
    field :user_id, :binary_id
    field :rating, :integer
    field :body, :string
    field :locale, :string
    field :edited_at, :utc_datetime_usec
    field :reply_body, :string
    field :replied_at, :utc_datetime_usec
    field :replied_by_id, :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(review, attrs) do
    review
    |> cast(attrs, ~w(user_id rating body locale edited_at reply_body replied_at replied_by_id)a)
    |> validate_required([:user_id, :rating])
    |> check_constraint(:rating, name: :box_reviews_check)
    |> unique_constraint([:organization_id, :user_id], name: :box_reviews_organization_id_user_id_index)
  end
end

defmodule Palee.ReviewAsks.BoxReviewReport do
  @moduledoc """
  A report on an in-app review of a box (ADR-397): who reported it, as a
  member or as the box, why, what the review said then, and how the Palee
  team's decision closed it.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "box_review_reports" do
    field :organization_id, :binary_id, read_after_writes: true
    field :review_id, :binary_id
    field :review_author_id, :binary_id
    field :reporter_id, :binary_id
    field :reporter_role, :string
    field :reason, :string
    field :note, :string
    field :review_rating, :integer
    field :review_body, :string
    field :status, :string, default: "open"
    field :decision_id, :binary_id
    field :decided_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(report, attrs) do
    report
    |> cast(attrs, ~w(review_id review_author_id reporter_id reporter_role reason note
                      review_rating review_body)a)
    |> validate_required(~w(review_id review_author_id reporter_id reporter_role reason
                            review_rating)a)
    |> check_constraint(:reason, name: :box_review_reports_check)
    |> unique_constraint([:review_id, :reporter_id],
      name: :box_review_reports_open_pair_index,
      message: "already_reported"
    )
  end
end

defmodule Palee.ReviewAsks.BoxReviewDecision do
  @moduledoc """
  The Palee team's decision on a reported review (ADR-397): the outcome
  (`keep`, `hide`, `remove`), its ground and the statement of reasons the
  author receives (DSA Art. 17), who decided and when.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "box_review_decisions" do
    field :organization_id, :binary_id, read_after_writes: true
    field :review_id, :binary_id
    field :review_author_id, :binary_id
    field :outcome, :string
    field :ground, :string
    field :statement, :string
    field :reports_count, :integer, default: 0
    field :decided_by_id, :binary_id
    field :decided_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(decision, attrs) do
    decision
    |> cast(attrs, ~w(review_id review_author_id outcome ground statement reports_count
                      decided_by_id decided_at)a)
    |> validate_required(~w(review_id review_author_id outcome ground decided_at)a)
    |> check_constraint(:outcome, name: :box_review_decisions_check)
  end
end

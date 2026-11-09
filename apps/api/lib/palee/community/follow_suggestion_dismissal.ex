defmodule Palee.Community.FollowSuggestionDismissal do
  @moduledoc """
  A person's ✕ on one suggested person in «Ίσως γνωρίζεις» (ADR-561). The
  suggested person comes back only if they start following the viewer
  after it.
  """

  use Ecto.Schema

  @primary_key false
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  schema "community_follow_suggestion_dismissals" do
    field :user_id, :binary_id, primary_key: true
    field :target_id, :binary_id, primary_key: true
    field :dismissed_at, :utc_datetime_usec
  end
end

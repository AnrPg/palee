defmodule Palee.ReviewAsks.ReviewAskOptOut do
  @moduledoc "A member who asked never to be asked for a review again (ADR-355)."

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "review_ask_opt_outs" do
    field :organization_id, :binary_id, read_after_writes: true
    field :user_id, :binary_id
    field :opted_out_at, :utc_datetime_usec
  end
end

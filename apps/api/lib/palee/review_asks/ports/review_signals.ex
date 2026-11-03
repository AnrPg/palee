defmodule Palee.ReviewAsks.Ports.ReviewSignals do
  @moduledoc """
  ADR-355: the behavioural facts behind a review ask, read in the box's
  tenant context (`config :palee, :review_signals`). Never a sentiment.
  """

  @callback facts(context :: map(), user_id :: Ecto.UUID.t()) :: %{
              active_membership: boolean(),
              member_since: DateTime.t() | nil,
              attendance_count: non_neg_integer(),
              last_attended_at: DateTime.t() | nil
            }
end

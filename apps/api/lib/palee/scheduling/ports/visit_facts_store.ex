defmodule Palee.Scheduling.Ports.VisitFactsStore do
  @moduledoc """
  ADR-359 (CP-E1): what the box knows about people's earlier visits, read
  for the visit badges of a class list or a check-in.
  """

  @type visit_counts :: %{box_visits: non_neg_integer(), type_visits: non_neg_integer() | nil}

  @doc """
  For each of `user_ids`: visits before `before` (attended or approved
  classes that already started, other than `exclude_class_ids`, and
  check-ins), and how many of those classes were of `class_type_id` (nil
  when no type is given).
  """
  @callback visit_counts(map(), [Ecto.UUID.t()], DateTime.t(), Ecto.UUID.t() | nil, [
              Ecto.UUID.t()
            ]) :: %{Ecto.UUID.t() => visit_counts()}

  @doc "Each person's latest referral attribution at the box: channel, referrer, event."
  @callback referrals(map(), [Ecto.UUID.t()]) :: %{Ecto.UUID.t() => map()}
end

defmodule Palee.Places.Ports.DiscoveryStore do
  @moduledoc """
  Cross-gym discovery of public items near a place (ADR-154). Answers carry
  ids, public coordinates and distances in metres; the cards are read
  elsewhere, through the usual policies. `area` is a `SearchArea`, `plan`
  an `AroundPlan`.
  """

  @type kind :: String.t()
  @type row :: map()

  @callback search(
              context :: map(),
              kind(),
              area :: map(),
              plan :: map(),
              cursor :: map() | nil,
              limit :: pos_integer()
            ) :: {[row()], non_neg_integer()}

  @doc """
  The same town fallback (ADR-583): boxes and open clubs whose location's
  town is one of `towns`, pinned or not, measured from the nearest of
  `points` when pinned (nil distance otherwise, listed last). First page
  only; other kinds have no town and find nothing.
  """
  @callback search_town(
              context :: map(),
              kind(),
              points :: [{float(), float()}],
              towns :: [String.t()],
              plan :: map(),
              limit :: pos_integer()
            ) :: {[row()], non_neg_integer()}

  @callback counts(context :: map(), area :: map(), plan :: map(), radii_m :: [float()]) ::
              %{kind() => %{float() => non_neg_integer()}}

  @callback pins(context :: map(), area :: map(), plan :: map(), limit :: pos_integer()) :: [
              row()
            ]

  @doc """
  Which of `user_ids` show in Γύρω μου with a main neighbourhood within
  `radius_m` of the context user's own (Partners distance, ADR-197).
  """
  @callback people_within(context :: map(), user_ids :: [binary()], radius_m :: number()) :: [
              binary()
            ]
end

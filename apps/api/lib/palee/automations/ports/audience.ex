defmodule Palee.Automations.Ports.Audience do
  @moduledoc """
  ADR-346: the facts the daily recipes read from the rest of the box
  (attendance, subscription packages). A read model: the adapter reads
  other contexts' tables in the box's scope and never writes them.
  """

  @type context :: map()

  @doc """
  Active box members whose last attended class was `days` or more days
  before `today` but not more than `days + 30` (an old absence is win-back,
  not «σου λείψαμε»): `%{user_id, last_visit_on}`.
  """
  @callback absent_members(context(), Date.t(), pos_integer()) :: [
              %{user_id: Ecto.UUID.t(), last_visit_on: Date.t()}
            ]

  @doc """
  Active subscription packages that end from `today` to `today + days`,
  will not renew by themselves and have nothing after them:
  `%{user_id, subscription_id, package_name, ends_on}`.
  """
  @callback ending_subscriptions(context(), Date.t(), pos_integer()) :: [
              %{
                user_id: Ecto.UUID.t(),
                subscription_id: Ecto.UUID.t(),
                package_name: String.t() | nil,
                ends_on: Date.t()
              }
            ]
end

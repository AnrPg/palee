defmodule Palee.Application.AuthorizeWodAccess do
  @moduledoc """
  ADR-551: a member or athlete whose access has closed (unpaid after the
  grace period, or a membership or subscription that ended) does not
  receive the gym's workouts: the WOD content of classes, their personal
  programme, the WOD goals, scales, leaderboards and snapshots. Their own
  past results stay theirs (Journal). Staff are never gated, and a gym
  that does not run finance (no profile) keeps everything open.

  The one check every surface uses, so the rule lives in one place
  (`EntitlementPolicy.access_open/1`).
  """

  alias Palee.{Finance, Organizations}
  alias Palee.Finance.Domain.EntitlementPolicy

  @spec call(map(), String.t() | nil) ::
          :ok | {:error, :finance_entitlement_blocked | :finance_entitlement_inactive}
  def call(context, user_id) do
    if is_nil(user_id) or Organizations.staff?(context) do
      :ok
    else
      context
      |> Finance.get_effective_entitlement(user_id)
      |> EntitlementPolicy.access_open()
    end
  end

  @doc "The same rule for an entitlement already read (the member's own `/entitlement`)."
  @spec open?(map() | nil) :: boolean()
  def open?(entitlement), do: EntitlementPolicy.access_open(entitlement) == :ok

  @spec allowed?(map(), String.t() | nil) :: boolean()
  def allowed?(context, user_id), do: call(context, user_id) == :ok
end

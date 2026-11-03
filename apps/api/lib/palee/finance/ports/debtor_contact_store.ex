defmodule Palee.Finance.Ports.DebtorContactStore do
  @moduledoc """
  ADR-450: storage of the contact a box keeps for a deleted profile that
  still owes it money. Every call runs inside the box's tenant scope.
  """

  @type contact :: %{
          membership_id: Ecto.UUID.t(),
          user_id: Ecto.UUID.t(),
          display_name: String.t(),
          email: String.t() | nil,
          phone_e164: String.t() | nil,
          locale: String.t(),
          kept_at: DateTime.t()
        }

  @doc "Keeps the contact of a membership (once: a repeat changes nothing)."
  @callback keep(map()) :: :ok | {:error, Ecto.Changeset.t()}

  @doc "The contacts kept for these people in the box, by user id."
  @callback for_users([Ecto.UUID.t()]) :: %{Ecto.UUID.t() => contact()}

  @doc "Every contact the box keeps."
  @callback list() :: [contact()]

  @doc "Deletes the contacts of these memberships."
  @callback release([Ecto.UUID.t()]) :: non_neg_integer()
end

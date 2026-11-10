defmodule Palee.Finance.Ports.MemberBenefitStore do
  @moduledoc """
  ADR-612: where a box keeps what it gave its members for free, as a
  ledger that is only added to. Every call runs inside the caller's tenant
  scope (`Finance.with_tenant_context/2`).
  """

  @doc "Adds one grant or revocation row (`Palee.Finance.MemberBenefit`)."
  @callback insert(map()) :: {:ok, map()} | {:error, term()}

  @doc "The row already written for an idempotency key, or nil."
  @callback by_idempotency_key(String.t()) :: map() | nil

  @doc "One grant of a membership, locked until the transaction ends, or nil."
  @callback lock_grant(Ecto.UUID.t(), Ecto.UUID.t()) :: map() | nil

  @doc "Every row of a membership, newest first."
  @callback list(Ecto.UUID.t()) :: [map()]

  @doc "ADR-633: the system's own grants with this reason (the package rule's rollout), newest first."
  @callback list_system_grants(String.t()) :: [map()]

  @doc """
  The grace or free access covering `today` that lasts longest, as
  `%{kind, until}`, or nil.
  """
  @callback access(Ecto.UUID.t(), Date.t()) :: %{kind: String.t(), until: Date.t()} | nil

  @doc "Runs `fun` in one database transaction; `{:error, reason}` from it rolls back."
  @callback transaction((-> {:ok, term()} | {:error, term()})) :: {:ok, term()} | {:error, term()}
end

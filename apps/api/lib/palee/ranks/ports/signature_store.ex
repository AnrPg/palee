defmodule Palee.Ranks.Ports.SignatureStore do
  @moduledoc """
  Persistence port of coaches' diploma signatures (ADR-377 addendum). Rows
  are the person's own: calls run in the person's session or a system one
  (no acting person), through `Palee.Ranks.SignatureStore.run/2`.
  """

  alias Palee.Ranks.{DiplomaSignature, DiplomaSignatureEvent}

  @type id :: Ecto.UUID.t()

  @doc "The person's current signature."
  @callback current(user_id :: id()) :: DiplomaSignature.t() | nil
  @doc "A signature by id, current or retired."
  @callback get(id()) :: DiplomaSignature.t() | nil
  @doc "Every signature row of the person, current and retired."
  @callback list(user_id :: id()) :: [DiplomaSignature.t()]
  @doc "Retires the current signature, inserts `attrs` as the new one and records `set`."
  @callback replace(user_id :: id(), attrs :: map(), DateTime.t()) ::
              {:ok, DiplomaSignature.t()} | {:error, term()}
  @doc "Deletes every signature row of the person and records `removed`; answers the deleted rows."
  @callback remove(user_id :: id(), DateTime.t()) :: {:ok, [DiplomaSignature.t()]}
  @doc "The person's audit trail, newest first."
  @callback events(user_id :: id()) :: [DiplomaSignatureEvent.t()]
end

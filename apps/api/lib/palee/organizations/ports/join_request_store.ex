defmodule Palee.Organizations.Ports.JoinRequestStore do
  @moduledoc """
  ADR-552: where «Ζήτα να γίνεις μέλος» requests are kept. Every call runs
  inside the caller's scope (`JoinRequestStore.with_scope/2`): the box's
  (`organization_id`) for its requests, the person's (`user_id`) for their
  own. Requests come back as plain maps.
  """

  @type request :: map()

  @doc "Creates an open request, or returns the person's open one (`:existing`)."
  @callback ask(Ecto.UUID.t()) :: {:ok, request(), :created | :existing} | {:error, term()}

  @callback get(Ecto.UUID.t()) :: request() | nil

  @doc "The person's latest request at the box in scope, open or not."
  @callback latest_for(Ecto.UUID.t()) :: request() | nil

  @doc "Open requests of the box in scope, oldest first."
  @callback list_open() :: [request()]

  @doc """
  ADR-638: of `organization_ids`, those where the person has an open
  request. Runs in the person's own scope (no box), across boxes.
  """
  @callback open_organization_ids(Ecto.UUID.t(), [Ecto.UUID.t()]) :: [Ecto.UUID.t()]

  @doc "Closes an open request under a row lock (`accepted`, `declined`, `cancelled`)."
  @callback close(Ecto.UUID.t(), map()) :: {:ok, request()} | {:error, term()}
end

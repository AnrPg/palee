defmodule Palee.Access.Ports.AccessStore do
  @moduledoc """
  Persistence of door controllers and the access log (ADR-381). Every
  callback but `lookup_door/1` takes the tenant context first.
  """

  @type context :: map()
  @type id :: Ecto.UUID.t()

  @doc "The box of a door controller, before any tenant session (provider events)."
  @callback lookup_door(id()) :: id() | nil
  @callback list_doors(context(), map()) :: [map()]
  @doc "The door with decoded credentials, or nil."
  @callback get_door(context(), id()) :: map() | nil
  @callback insert_door(context(), map()) :: {:ok, map()} | {:error, term()}
  @callback update_door(context(), id(), map()) :: {:ok, map()} | {:error, term()}
  @callback delete_door(context(), id()) :: :ok
  @callback insert_event(context(), map()) :: {:ok, map()} | {:error, term()}
  @callback list_events(context(), map()) :: %{events: [map()], total: non_neg_integer()}
  @callback purge_events(context(), before :: DateTime.t()) :: non_neg_integer()
end

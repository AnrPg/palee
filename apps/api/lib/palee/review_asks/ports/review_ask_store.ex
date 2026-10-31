defmodule Palee.ReviewAsks.Ports.ReviewAskStore do
  @moduledoc "Persistence of review asks (ADR-355); every callback takes the tenant context first."

  @type context :: map()
  @type id :: Ecto.UUID.t()

  @callback get_settings(context()) :: map() | nil
  @callback save_settings(context(), map(), lock_version :: non_neg_integer()) ::
              {:ok, map()} | {:error, :stale | term()}
  @callback list_asks(context(), user_id :: id()) :: [map()]
  @callback insert_ask(context(), map()) :: {:ok, map()} | {:error, :already_asked | term()}
  @callback get_ask(context(), id(), user_id :: id()) :: map() | nil
  @callback update_ask(context(), id(), map()) :: {:ok, map()} | {:error, term()}
  @callback opted_out?(context(), user_id :: id()) :: boolean()
  @callback opt_out(context(), user_id :: id(), DateTime.t()) :: :ok
  @callback opt_in(context(), user_id :: id()) :: :ok
  @callback summary(context(), since :: DateTime.t()) :: %{atom() => non_neg_integer()}
end

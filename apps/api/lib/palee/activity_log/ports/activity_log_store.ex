defmodule Palee.ActivityLog.Ports.ActivityLogStore do
  @moduledoc "ADR-760: where the «Αρχείο ενεργειών» lives. Calls run in the tenant's session."

  @type entry :: map()
  @type filters :: %{
          optional(:areas) => [String.t()],
          optional(:own_areas) => [String.t()],
          optional(:reader_id) => Ecto.UUID.t(),
          optional(:person_user_id) => Ecto.UUID.t(),
          optional(:actor_user_id) => Ecto.UUID.t(),
          optional(:actions) => [String.t()],
          optional(:from) => DateTime.t(),
          optional(:to) => DateTime.t(),
          optional(:query) => String.t(),
          optional(:matching_user_ids) => [Ecto.UUID.t()],
          optional(:shared_only) => boolean(),
          optional(:sensitive_only) => boolean(),
          optional(:before) => {DateTime.t(), Ecto.UUID.t()},
          optional(:limit) => pos_integer()
        }

  @callback insert(map()) :: {:ok, entry()} | {:error, term()}
  @callback insert_all_new([map()]) :: non_neg_integer()
  @callback list(filters()) :: [entry()]
  @callback get(Ecto.UUID.t()) :: entry() | nil
  @callback forget_person(Ecto.UUID.t()) :: non_neg_integer()
  @callback people_ids() :: [Ecto.UUID.t()]
  @callback backfill_version() :: non_neg_integer() | nil
  @callback mark_backfilled(non_neg_integer(), non_neg_integer()) :: :ok
end

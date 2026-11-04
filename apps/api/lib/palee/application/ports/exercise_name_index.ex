defmodule Palee.Application.Ports.ExerciseNameIndex do
  @moduledoc """
  ADR-461: where exercise-name suggestions come from. Remembers the names
  people and boxes typed (`user` and `org` owners), searches them with the
  Palee catalog, and rebuilds the search store from Postgres.
  """

  @type owner ::
          %{scope: :user, user_id: Ecto.UUID.t()}
          | %{scope: :org, organization_id: Ecto.UUID.t()}
  @type viewer :: %{
          required(:user_id) => Ecto.UUID.t(),
          optional(:organization_id) => Ecto.UUID.t() | nil
        }
  @type hit :: %{
          required(:name) => String.t(),
          required(:catalog_slug) => String.t() | nil,
          optional(:uses_count) => non_neg_integer(),
          optional(:category) => String.t() | nil
        }

  @doc "Queues remembering `rows` (`%{name, catalog_slug}`) for `owner`, counted `increment` more uses."
  @callback enqueue_record(owner(), [map()], non_neg_integer()) :: :ok | {:error, term()}

  @doc """
  Remembers cleaned entries (`%{name, folded, catalog_slug}`) for `owner` now
  (the queued job's work); returns the folded names the owner typed for the
  first time.
  """
  @callback record(owner(), [map()], non_neg_integer()) :: {:ok, [String.t()]} | {:error, term()}

  @doc """
  Hits per source for what the viewer typed; `box` only for the given
  organization. `catalog` is the Palee catalog (`Workouts.exercise_catalog_documents/0`).
  """
  @callback search(viewer(), String.t(), pos_integer(), catalog :: [map()]) ::
              {:ok, %{mine: [hit()], box: [hit()], palee: [hit()]}} | {:error, term()}

  @doc "Rebuilds the search store: the catalog and the remembered names of `owners`."
  @callback rebuild([owner()], catalog :: [map()]) :: {:ok, non_neg_integer()} | {:error, term()}

  @doc "Replaces the Palee scope of the search store (after an approved addition)."
  @callback refresh_catalog(catalog :: [map()]) :: :ok | {:error, term()}
end

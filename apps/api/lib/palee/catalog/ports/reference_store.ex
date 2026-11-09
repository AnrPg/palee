defmodule Palee.Catalog.Ports.ReferenceStore do
  @moduledoc """
  ADR-560: reads the reference catalog tables (muscles, fitness qualities,
  exercises, aliases and exercise targets). Read-only: the Palee team's
  catalog decisions are written by `Workouts.Ports.ExerciseCatalogStore`,
  together with their audit events.
  """

  alias Palee.Catalog.Domain.Reference

  @doc "Every row of the reference catalog, with the current revision."
  @callback load() :: {:ok, Reference.rows()} | {:error, term()}

  @doc "The revision every write to the reference tables bumps."
  @callback revision() :: {:ok, non_neg_integer()} | {:error, term()}
end

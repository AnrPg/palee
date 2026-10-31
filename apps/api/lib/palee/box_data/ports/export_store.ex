defmodule Palee.BoxData.Ports.ExportStore do
  @moduledoc """
  ADR-365: storage of the box's data export requests. Every call runs in the
  box's tenant session (row-level security on `organization_id`).
  """

  alias Palee.BoxData.Export

  @type id :: Ecto.UUID.t()

  @doc "The box's requests, newest first."
  @callback list(id()) :: [Export.t()]
  @callback get(id(), id()) :: Export.t() | nil
  @callback insert(map()) :: {:ok, Export.t()} | {:error, Ecto.Changeset.t()}

  @doc "Moves a pending request to `ready` or `failed` (row locked); other states are left."
  @callback finish(Export.t(), map()) ::
              {:ok, Export.t()} | {:error, :not_pending | Ecto.Changeset.t()}
end

defmodule Palee.Catalog.ReferenceStore do
  @moduledoc "Facade over the reference catalog store adapter (ADR-560)."

  @behaviour Palee.Catalog.Ports.ReferenceStore

  defp adapter, do: Application.fetch_env!(:palee, :reference_catalog_store)

  @impl true
  def load, do: adapter().load()

  @impl true
  def revision, do: adapter().revision()
end

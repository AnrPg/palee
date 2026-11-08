defmodule Palee.Finance.PackageAudienceStore do
  @moduledoc "ADR-553: dispatches to the configured `Palee.Finance.Ports.PackageAudienceStore`."

  @behaviour Palee.Finance.Ports.PackageAudienceStore

  defp adapter, do: Application.fetch_env!(:palee, :package_audience_store)

  @impl true
  def load, do: adapter().load()
  @impl true
  def set_box(audience), do: adapter().set_box(audience)
  @impl true
  def set_package(id, audience), do: adapter().set_package(id, audience)
  @impl true
  def put_exception(params), do: adapter().put_exception(params)
  @impl true
  def delete_exception(id), do: adapter().delete_exception(id)
  @impl true
  def holdings(user_id), do: adapter().holdings(user_id)
end

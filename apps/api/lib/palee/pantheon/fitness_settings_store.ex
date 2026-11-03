defmodule Palee.Pantheon.FitnessSettingsStore do
  @moduledoc """
  ADR-395: the fitness card's settings through the configured adapter. Every
  call runs inside the caller's RLS scope (`Pantheon.with_user_context/2` or
  `with_tenant_context/2`).
  """

  @behaviour Palee.Pantheon.Ports.FitnessSettingsStore

  defp adapter, do: Application.fetch_env!(:palee, :fitness_settings_store)

  @impl true
  def get_settings(user_id), do: adapter().get_settings(user_id)

  @impl true
  def put_settings(user_id, params), do: adapter().put_settings(user_id, params)

  @impl true
  def coach_client_settings(client_user_id), do: adapter().coach_client_settings(client_user_id)

  @impl true
  def list_overrides_for_client(client_user_id),
    do: adapter().list_overrides_for_client(client_user_id)

  @impl true
  def get_override(organization_id, client_user_id),
    do: adapter().get_override(organization_id, client_user_id)

  @impl true
  def put_override(params), do: adapter().put_override(params)

  @impl true
  def delete_override(organization_id, client_user_id),
    do: adapter().delete_override(organization_id, client_user_id)
end

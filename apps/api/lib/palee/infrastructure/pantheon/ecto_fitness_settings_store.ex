defmodule Palee.Infrastructure.Pantheon.EctoFitnessSettingsStore do
  @moduledoc "ADR-395: Postgres storage of the fitness card's settings (RLS-scoped)."

  @behaviour Palee.Pantheon.Ports.FitnessSettingsStore

  import Ecto.Query

  alias Palee.Pantheon.{FitnessDisplayOverride, FitnessSettings}
  alias Palee.Repo

  @impl true
  def get_settings(user_id) do
    FitnessSettings
    |> where([s], s.user_id == ^user_id)
    |> Repo.one()
    |> normalize_settings()
  end

  @impl true
  def put_settings(user_id, params) do
    existing = Repo.get(FitnessSettings, user_id) || %FitnessSettings{user_id: user_id}

    existing
    |> FitnessSettings.changeset(Map.put(params, :user_id, user_id))
    |> Repo.insert_or_update()
    |> case do
      {:ok, saved} -> {:ok, normalize_settings(saved)}
      error -> error
    end
  end

  @impl true
  def coach_client_settings(client_user_id) do
    case Repo.query!(
           "SELECT body_weight_kg, birth_year, display FROM palee_coach_client_fitness_settings($1)",
           [Ecto.UUID.dump!(client_user_id)]
         ) do
      %{rows: [[weight, year, display]]} ->
        %{body_weight_kg: decimal(weight), birth_year: year, display: display}

      _none ->
        nil
    end
  end

  @impl true
  def list_overrides_for_client(client_user_id) do
    FitnessDisplayOverride
    |> where([o], o.client_user_id == ^client_user_id)
    |> Repo.all()
    |> Enum.map(&normalize_override/1)
  end

  @impl true
  def get_override(organization_id, client_user_id) do
    FitnessDisplayOverride
    |> where([o], o.organization_id == ^organization_id and o.client_user_id == ^client_user_id)
    |> Repo.one()
    |> case do
      nil -> nil
      override -> normalize_override(override)
    end
  end

  @impl true
  def put_override(params) do
    %FitnessDisplayOverride{}
    |> FitnessDisplayOverride.changeset(params)
    |> Repo.insert(
      on_conflict: {:replace, [:display, :set_by_id, :updated_at]},
      conflict_target: [:organization_id, :client_user_id],
      returning: true
    )
    |> case do
      {:ok, saved} -> {:ok, normalize_override(saved)}
      error -> error
    end
  end

  @impl true
  def delete_override(organization_id, client_user_id) do
    FitnessDisplayOverride
    |> where([o], o.organization_id == ^organization_id and o.client_user_id == ^client_user_id)
    |> Repo.delete_all()

    :ok
  end

  defp normalize_settings(nil), do: nil

  defp normalize_settings(%FitnessSettings{} = settings) do
    %{
      body_weight_kg: decimal(settings.body_weight_kg),
      birth_year: settings.birth_year,
      display: settings.display
    }
  end

  defp normalize_override(%FitnessDisplayOverride{} = override) do
    %{
      organization_id: override.organization_id,
      client_user_id: override.client_user_id,
      display: override.display,
      set_by_id: override.set_by_id,
      updated_at: override.updated_at
    }
  end

  defp decimal(nil), do: nil
  defp decimal(%Decimal{} = value), do: Decimal.to_float(value)
  defp decimal(value) when is_number(value), do: value * 1.0
end

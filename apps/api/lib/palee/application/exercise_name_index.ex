defmodule Palee.Application.ExerciseNameIndex do
  @moduledoc """
  ADR-461: facade over the configured exercise-name index (Meilisearch in
  production with a Postgres fallback, Postgres alone in test). `remember_*`
  are the save-path hooks: they queue the work and never fail the save.
  """

  @behaviour Palee.Application.Ports.ExerciseNameIndex

  require Logger

  @impl true
  def enqueue_record(owner, rows, increment), do: impl().enqueue_record(owner, rows, increment)
  @impl true
  def record(owner, rows, increment), do: impl().record(owner, rows, increment)
  @impl true
  def search(viewer, query, limit, catalog), do: impl().search(viewer, query, limit, catalog)
  @impl true
  def rebuild(owners, catalog), do: impl().rebuild(owners, catalog)
  @impl true
  def refresh_catalog(catalog), do: impl().refresh_catalog(catalog)

  @doc "A person's own names (training log, PRs); `new?` counts one more use."
  def remember_for_user(user_id, rows, new? \\ true)

  def remember_for_user(user_id, rows, new?) when is_binary(user_id) and is_list(rows),
    do: remember(%{scope: :user, user_id: user_id}, rows, new?)

  def remember_for_user(_user_id, _rows, _new?), do: :ok

  @doc "A box's names (its published WODs)."
  def remember_for_organization(organization_id, rows)
      when is_binary(organization_id) and is_list(rows),
      do: remember(%{scope: :org, organization_id: organization_id}, rows, true)

  def remember_for_organization(_organization_id, _rows), do: :ok

  defp remember(owner, rows, new?) do
    case Enum.filter(rows, &is_map/1) do
      [] ->
        :ok

      rows ->
        case enqueue_record(owner, rows, if(new?, do: 1, else: 0)) do
          :ok ->
            :ok

          {:error, reason} ->
            Logger.warning("exercise names not queued: #{inspect(reason)}")
            :ok
        end
    end
  end

  defp impl, do: Application.fetch_env!(:palee, :exercise_name_index)
end

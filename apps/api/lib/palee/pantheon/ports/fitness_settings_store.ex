defmodule Palee.Pantheon.Ports.FitnessSettingsStore do
  @moduledoc "ADR-395: storage of the fitness card's settings and coach overrides."

  @callback get_settings(user_id :: Ecto.UUID.t()) :: map() | nil
  @callback put_settings(user_id :: Ecto.UUID.t(), params :: map()) ::
              {:ok, map()} | {:error, Ecto.Changeset.t()}
  @callback coach_client_settings(client_user_id :: Ecto.UUID.t()) :: map() | nil
  @callback list_overrides_for_client(client_user_id :: Ecto.UUID.t()) :: [map()]
  @callback get_override(organization_id :: Ecto.UUID.t(), client_user_id :: Ecto.UUID.t()) ::
              map() | nil
  @callback put_override(map()) :: {:ok, map()} | {:error, Ecto.Changeset.t()}
  @callback delete_override(organization_id :: Ecto.UUID.t(), client_user_id :: Ecto.UUID.t()) ::
              :ok
end

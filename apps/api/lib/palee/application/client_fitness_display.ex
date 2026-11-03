defmodule Palee.Application.ClientFitnessDisplay do
  @moduledoc """
  ADR-395: a coach and «Επίπεδο φυσικής κατάστασης» of a client they coach
  (an active coaching relationship in the box; owners and admins who do not
  coach the client get `:not_your_client`, ANR 2026-11-03).

    * `get/2` – the client's body weight, birth year and own choice (through
      `palee_coach_client_fitness_settings`, which checks the relationship
      again in the database) and the box's override, if any;
    * `put/3` – `progress_only` or `none` for the client in this box, or
      `nil` to give the choice back to the client. The client's card then
      says «Το όρισε ο coach σου».
  """

  alias Palee.{Coaching, Pantheon}
  alias Palee.Pantheon.FitnessSettingsStore

  @displays ~w(progress_only none)

  def get(%{organization_id: organization_id, user_id: coach_id} = context, client_id)
      when is_binary(organization_id) and is_binary(coach_id) do
    with :ok <- authorize(context, client_id) do
      Pantheon.with_tenant_context(context, fn ->
        {:ok, view(organization_id, client_id)}
      end)
    end
  end

  def get(_context, _client_id), do: {:error, :forbidden}

  def put(%{organization_id: organization_id, user_id: coach_id} = context, client_id, display)
      when is_binary(organization_id) and is_binary(coach_id) do
    with :ok <- authorize(context, client_id),
         :ok <- valid(display) do
      Pantheon.with_tenant_context(context, fn ->
        result =
          case display do
            nil ->
              FitnessSettingsStore.delete_override(organization_id, client_id)

            display ->
              FitnessSettingsStore.put_override(%{
                organization_id: organization_id,
                client_user_id: client_id,
                display: display,
                set_by_id: coach_id
              })
          end

        with :ok <- ok(result), do: {:ok, view(organization_id, client_id)}
      end)
    end
  end

  def put(_context, _client_id, _display), do: {:error, :forbidden}

  defp view(organization_id, client_id) do
    override = FitnessSettingsStore.get_override(organization_id, client_id)

    %{
      settings: FitnessSettingsStore.coach_client_settings(client_id),
      override: override && override.display
    }
  end

  defp authorize(context, client_id) do
    if Coaching.coaches?(context, context.user_id, client_id),
      do: :ok,
      else: {:error, :not_your_client}
  end

  defp valid(nil), do: :ok
  defp valid(display) when display in @displays, do: :ok
  defp valid(_display), do: {:error, :invalid_fitness_display}

  defp ok(:ok), do: :ok
  defp ok({:ok, _saved}), do: :ok
  defp ok(error), do: error
end

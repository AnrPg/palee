defmodule Palee.Application.Access.DoorSettings do
  @moduledoc """
  Staff › Settings › branch › «Πόρτες» (ADR-381): the doors of each branch
  and their controllers (owners, admins and branch managers with
  `manage_locations`), opening a door from the desk (`check_in`), and the
  access log.

  Controller secrets are written, never read back. The event URL with its
  token is shown when a door is made or its token renewed, for the
  provider's own notifications (a Shelly action, a Kisi webhook).
  """

  alias Palee.Access
  alias Palee.Application.PublicURL

  def catalog,
    do: %{
      providers: Access.providers() -- sandbox_hidden(),
      who: Access.entry_whos(),
      defaults: Palee.Access.Domain.EntryRules.defaults(),
      log_days: Access.log_days()
    }

  defp sandbox_hidden,
    do: if(Application.get_env(:palee, :open_platform_sandbox, false), do: [], else: ["sandbox"])

  def list(context, params) do
    filters =
      %{location_id: param(params, :location_id)} |> Map.reject(fn {_k, v} -> is_nil(v) end)

    %{doors: context |> Access.list_doors(filters) |> scoped(context)}
  end

  @doc "`{:ok, %{door, event_url}}`: the event URL carries a token shown once."
  def create(context, params) do
    with :ok <- authorize_location(context, param(params, :location_id)),
         {:ok, %{door: door, event_token: token}} <-
           Access.create_door(context, attrs(params), context.user_id) do
      {:ok, %{door: door, event_url: event_url(door.id, token)}}
    end
  end

  def update(context, id, params) do
    with {:ok, door} <- Access.get_door(context, id),
         :ok <- authorize_location(context, door.location_id) do
      Access.update_door(context, id, Map.take(attrs(params), present(params)), context.user_id)
    end
  end

  def delete(context, id) do
    with {:ok, door} <- Access.get_door(context, id),
         :ok <- authorize_location(context, door.location_id),
         do: Access.delete_door(context, id)
  end

  def rotate_event_token(context, id) do
    with {:ok, door} <- Access.get_door(context, id),
         :ok <- authorize_location(context, door.location_id),
         {:ok, token} <- Access.rotate_event_token(context, id),
         do: {:ok, %{event_url: event_url(id, token)}}
  end

  @doc """
  «Άνοιγμα» from the desk (`check_in`): opens the door and logs who did it.
  `{:ok, %{opened: true}}` or `{:error, :door_offline | ...}`.
  """
  def unlock(context, id, now \\ DateTime.utc_now()) do
    with %{} = door <- Access.door_for_unlock(context, id) || {:error, :not_found},
         :ok <- authorize_location(context, door.location_id),
         true <- door.status == "active" || {:error, :door_disabled} do
      result = Access.unlock(context, door, now)

      Access.record(context, %{
        door_controller_id: door.id,
        location_id: door.location_id,
        actor_id: context.user_id,
        kind: if(result == :ok, do: "staff_unlock", else: "unlock_failed"),
        reason: if(result == :ok, do: "staff", else: elem(result, 1) |> to_string()),
        method: "staff",
        occurred_at: now
      })

      with :ok <- result, do: {:ok, %{opened: true}}
    end
  end

  def events(context, params) do
    filters =
      %{
        door_id: param(params, :door_id),
        location_id: param(params, :location_id),
        user_id: param(params, :user_id),
        kind: param(params, :kind),
        limit: param(params, :limit),
        offset: param(params, :offset)
      }
      |> Map.reject(fn {_key, value} -> is_nil(value) end)

    Access.list_events(context, filters)
  end

  defp attrs(params) do
    %{
      name: param(params, :name),
      location_id: param(params, :location_id),
      provider: param(params, :provider),
      settings: param(params, :settings),
      credentials: param(params, :credentials),
      rules: param(params, :rules),
      status: param(params, :status)
    }
  end

  defp present(params) do
    Enum.filter([:name, :settings, :credentials, :rules, :status], fn key ->
      Map.has_key?(params, key) or Map.has_key?(params, Atom.to_string(key))
    end)
  end

  # ADR-186: branch-scoped staff manage and open only their branches' doors.
  defp authorize_location(context, location_id) do
    case Map.get(context, :location_scope, :all) do
      :all -> :ok
      ids when is_list(ids) -> if location_id in ids, do: :ok, else: {:error, :forbidden}
    end
  end

  defp scoped(doors, context) do
    case Map.get(context, :location_scope, :all) do
      :all -> doors
      ids -> Enum.filter(doors, &(&1.location_id in ids))
    end
  end

  defp event_url(door_id, token),
    do:
      (PublicURL.base_url() |> String.trim_trailing("/")) <>
        "/api/access/doors/#{door_id}/events?token=#{token}"

  defp param(params, key), do: Map.get(params, key, Map.get(params, Atom.to_string(key)))
end

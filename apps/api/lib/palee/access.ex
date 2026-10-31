defmodule Palee.Access do
  @moduledoc """
  Door access control (ADR-381, CP-E3): the doors of each branch with the
  controller that opens them (sandbox, Shelly relay, Kisi), who may enter
  when (`EntryRules`), opening, and the access log of every grant, refusal,
  failed unlock, staff opening and door event.

  Controllers are fail-secure: when one cannot be reached the door stays
  locked and the log says `unlock_failed` (`door_offline`); nothing queues
  an unlock for later. The log is kept #{180} days.
  """

  alias Palee.Access.AccessStore
  alias Palee.Access.Domain.{EntryRules, ProviderSettings}

  @log_days 180
  @event_kinds ~w(granted denied unlock_failed staff_unlock door_event)

  def log_days, do: @log_days
  def providers, do: ProviderSettings.providers()
  def entry_whos, do: EntryRules.whos()
  def event_kinds, do: @event_kinds

  defp sandbox?, do: Application.get_env(:palee, :open_platform_sandbox, false) == true

  @doc false
  def controller(provider) do
    :palee |> Application.get_env(:door_controllers, %{}) |> Map.fetch!(provider)
  end

  # ── Doors ───────────────────────────────────────────────────────────────

  def list_doors(context, filters \\ %{}),
    do: context |> AccessStore.list_doors(filters) |> Enum.map(&door_view/1)

  @doc "Active doors of a branch, with credentials, for opening."
  def doors_at(context, location_id),
    do: AccessStore.list_doors(context, %{location_id: location_id, status: "active"})

  def get_door(context, id) do
    case AccessStore.get_door(context, id) do
      nil -> {:error, :not_found}
      door -> {:ok, door_view(door)}
    end
  end

  @doc "The door with credentials (for opening), or nil."
  def door_for_unlock(context, id), do: AccessStore.get_door(context, id)

  @doc """
  A new door after its controller answered: `{:ok, %{door, event_token}}`.
  The event token (for the provider's own notifications) is in this answer
  only.
  """
  def create_door(context, params, actor_id) do
    provider = params[:provider]

    with true <- provider != "sandbox" or sandbox?() || {:error, :invalid_door_settings},
         {:ok, name} <- door_name(params[:name]),
         {:ok, location_id} <- uuid(params[:location_id]),
         {:ok, settings, credentials} <-
           ProviderSettings.validate(provider, params[:settings], params[:credentials]),
         {:ok, rules} <- EntryRules.normalize(params[:rules] || %{}),
         :ok <- check(provider, settings, credentials) do
      token = new_token()

      attrs = %{
        location_id: location_id,
        name: name,
        provider: provider,
        settings: settings,
        credentials: if(credentials == %{}, do: nil, else: credentials),
        rules: rules,
        event_token_hash: hash(token),
        status: "active",
        updated_by_id: actor_id
      }

      with {:ok, door} <- AccessStore.insert_door(context, attrs),
           do: {:ok, %{door: door_view(door), event_token: token}}
    end
  end

  @doc "Changes the name, rules, status or controller settings (checked again)."
  def update_door(context, id, params, actor_id) do
    with %{} = door <- AccessStore.get_door(context, id) || {:error, :not_found},
         {:ok, changes} <- door_changes(door, params) do
      with {:ok, door} <-
             AccessStore.update_door(context, id, Map.put(changes, :updated_by_id, actor_id)),
           do: {:ok, door_view(door)}
    end
  end

  defp door_changes(door, params) do
    with {:ok, name} <- optional(params, :name, &door_name/1),
         {:ok, rules} <- optional(params, :rules, &EntryRules.normalize/1),
         {:ok, status} <- optional(params, :status, &door_status/1),
         {:ok, controller} <- controller_changes(door, params) do
      {:ok,
       %{name: name, rules: rules, status: status}
       |> Map.reject(fn {_key, value} -> is_nil(value) end)
       |> Map.merge(controller)}
    end
  end

  defp controller_changes(door, params) do
    if Map.has_key?(params, :settings) or Map.has_key?(params, :credentials) do
      provider = door.provider

      with {:ok, settings, credentials} <-
             ProviderSettings.validate(
               provider,
               params[:settings] || door.settings,
               params[:credentials],
               door.credentials
             ),
           :ok <- check(provider, settings, credentials) do
        {:ok,
         %{
           settings: settings,
           credentials: if(credentials == %{}, do: nil, else: credentials),
           last_error: nil
         }}
      end
    else
      {:ok, %{}}
    end
  end

  defp optional(params, key, fun) do
    case Map.fetch(params, key) do
      {:ok, value} -> fun.(value)
      :error -> {:ok, nil}
    end
  end

  def delete_door(context, id) do
    case AccessStore.get_door(context, id) do
      nil -> {:error, :not_found}
      _door -> AccessStore.delete_door(context, id)
    end
  end

  @doc "A new event token for the door's provider notifications: `{:ok, token}`."
  def rotate_event_token(context, id) do
    token = new_token()

    with %{} <- AccessStore.get_door(context, id) || {:error, :not_found},
         {:ok, _door} <- AccessStore.update_door(context, id, %{event_token_hash: hash(token)}),
         do: {:ok, token}
  end

  defp check(provider, settings, credentials) do
    case controller(provider).check(%{
           provider: provider,
           settings: settings,
           credentials: credentials
         }) do
      :ok -> :ok
      {:error, {:unauthorized, _reason}} -> {:error, :door_unauthorized}
      {:error, {:offline, _reason}} -> {:error, :door_offline}
      {:error, {:rejected, _reason}} -> {:error, :door_not_found}
    end
  end

  defp door_name(name) when is_binary(name) do
    case String.trim(name) do
      "" -> {:error, :invalid_door_name}
      trimmed -> if String.length(trimmed) <= 80, do: {:ok, trimmed}, else: {:error, :invalid_door_name}
    end
  end

  defp door_name(_name), do: {:error, :invalid_door_name}

  defp door_status(status) when status in ["active", "disabled"], do: {:ok, status}
  defp door_status(_status), do: {:error, :invalid_door_status}

  defp uuid(value) do
    case Ecto.UUID.cast(value) do
      {:ok, id} -> {:ok, id}
      :error -> {:error, :invalid_location}
    end
  end

  defp door_view(door) do
    %{
      id: door.id,
      location_id: door.location_id,
      name: door.name,
      provider: door.provider,
      settings: door.settings,
      rules: door.rules,
      status: door.status,
      credentials_saved: door.credentials != %{},
      last_error: door.last_error,
      last_seen_at: door.last_seen_at,
      updated_at: door.updated_at
    }
  end

  # ── Opening ─────────────────────────────────────────────────────────────

  @doc "Whether `facts` may open the door now (see `EntryRules`)."
  def decide(door, facts, now, local), do: EntryRules.decide(facts, door.rules, now, local)

  @doc """
  Opens the door (a pulse of the door's `unlock_seconds`): `:ok` or
  `{:error, :door_offline | :door_unauthorized | :door_refused}`. Records
  the controller's health; the caller writes the access log.
  """
  def unlock(context, door, %DateTime{} = now) do
    seconds = Map.get(door.rules || %{}, "unlock_seconds", 5)

    case controller(door.provider).unlock(door, seconds) do
      :ok ->
        AccessStore.update_door(context, door.id, %{last_seen_at: now, last_error: nil})
        :ok

      {:error, {kind, reason}} ->
        AccessStore.update_door(context, door.id, %{last_error: failure_text(kind, reason)})
        {:error, failure(kind)}
    end
  end

  defp failure(:offline), do: :door_offline
  defp failure(:unauthorized), do: :door_unauthorized
  defp failure(:rejected), do: :door_refused

  defp failure_text(kind, reason),
    do: "#{kind}: #{inspect(reason)}" |> String.slice(0, 300)

  # ── The access log ──────────────────────────────────────────────────────

  @doc """
  One line of the log. `attrs`: `door_controller_id`, `location_id`,
  `user_id`, `actor_id`, `kind`, `reason`, `method`, `provider_event`,
  `occurred_at`.
  """
  def record(context, attrs), do: AccessStore.insert_event(context, attrs)

  def list_events(context, filters) do
    context
    |> AccessStore.list_events(filters)
    |> Map.update!(:events, fn events -> Enum.map(events, &event_view/1) end)
  end

  defp event_view(event) do
    Map.take(event, [
      :id,
      :door_controller_id,
      :location_id,
      :user_id,
      :actor_id,
      :kind,
      :reason,
      :method,
      :provider_event,
      :occurred_at
    ])
  end

  @doc "Removes log lines older than #{@log_days} days: the count."
  def purge_old_events(context, %DateTime{} = now),
    do: AccessStore.purge_events(context, DateTime.add(now, -@log_days * 86_400, :second))

  @doc """
  The door controller's own notification (provider events): `{:ok, count}`
  of log lines written, or `{:error, :not_found}` for an unknown door or a
  wrong token (the same answer, so ids cannot be probed).
  """
  def ingest_event(door_id, token, params, %DateTime{} = now) when is_binary(token) do
    with organization_id when is_binary(organization_id) <- AccessStore.lookup_door(door_id),
         context = %{organization_id: organization_id},
         %{} = door <- AccessStore.get_door(context, door_id),
         true <- is_binary(door.event_token_hash) and :crypto.hash_equals(hash(token), door.event_token_hash),
         {:ok, events} <- controller(door.provider).parse_event(door, params) do
      AccessStore.update_door(context, door.id, %{last_seen_at: now})

      Enum.each(events, fn event ->
        AccessStore.insert_event(context, %{
          door_controller_id: door.id,
          location_id: door.location_id,
          kind: "door_event",
          reason: "provider",
          method: "provider",
          provider_event: event.event,
          occurred_at: event.occurred_at || now
        })
      end)

      {:ok, length(events)}
    else
      {:error, :invalid_event} -> {:error, :invalid_door_event}
      _unknown -> {:error, :not_found}
    end
  end

  def ingest_event(_door_id, _token, _params, _now), do: {:error, :not_found}

  defp new_token, do: Base.url_encode64(:crypto.strong_rand_bytes(24), padding: false)
  defp hash(token), do: :crypto.hash(:sha256, token)

  # ── Tenant data (ADR-117) ───────────────────────────────────────────────

  def tenant_data_policy, do: Palee.Access.Domain.TenantDataPolicy.policy()

  def tenant_data_inventory(context),
    do: Palee.TenantData.TableStore.inventory(tenant_data_policy(), context)

  def export_tenant_data(context, mode \\ :full),
    do: Palee.TenantData.TableStore.export(tenant_data_policy(), context, mode)

  def purge_tenant_data(context),
    do: Palee.TenantData.TableStore.purge(tenant_data_policy(), context)
end

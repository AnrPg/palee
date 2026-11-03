defmodule Palee.Infrastructure.Status.EctoStatusStore do
  @moduledoc "Ecto adapter of `Palee.Status.Ports.StatusStore` (ADR-364)."

  @behaviour Palee.Status.Ports.StatusStore

  import Ecto.Query

  alias Palee.Repo
  alias Palee.Status.{ComponentState, DailySample, Incident, IncidentUpdate, Subscriber}

  ## Probes

  @impl true
  def record_probe(results, %DateTime{} = now) do
    day = DateTime.to_date(now)

    Repo.transaction(fn ->
      Enum.each(results, fn result ->
        upsert_state(result, now)
        add_sample(result, day)
      end)
    end)
    |> case do
      {:ok, _} -> :ok
      {:error, _reason} = error -> error
    end
  end

  defp upsert_state(%{component: component, status: status} = result, now) do
    Repo.insert_all(
      ComponentState,
      [
        %{
          component: component,
          status: status,
          reason: result |> Map.get(:reason) |> truncate(300),
          checked_at: now,
          changed_at: now
        }
      ],
      conflict_target: [:component],
      on_conflict:
        from(s in ComponentState,
          update: [
            set: [
              status: fragment("EXCLUDED.status"),
              reason: fragment("EXCLUDED.reason"),
              checked_at: fragment("EXCLUDED.checked_at"),
              changed_at:
                fragment(
                  "CASE WHEN ? = EXCLUDED.status THEN ? ELSE EXCLUDED.changed_at END",
                  s.status,
                  s.changed_at
                )
            ]
          ]
        )
    )
  end

  defp add_sample(%{component: component, status: status}, day) do
    counts = %{
      operational: if(status == "operational", do: 1, else: 0),
      degraded: if(status == "degraded", do: 1, else: 0),
      down: if(status == "down", do: 1, else: 0)
    }

    Repo.insert_all(
      DailySample,
      [Map.merge(counts, %{component: component, day: day, total: 1})],
      conflict_target: [:component, :day],
      on_conflict: [
        inc: [
          total: 1,
          operational: counts.operational,
          degraded: counts.degraded,
          down: counts.down
        ]
      ]
    )
  end

  @impl true
  def list_component_states, do: Repo.all(from(s in ComponentState, order_by: s.component))

  @impl true
  def list_samples(%Date{} = first, %Date{} = last) do
    DailySample
    |> where([s], s.day >= ^first and s.day <= ^last)
    |> order_by([s], asc: s.component, asc: s.day)
    |> Repo.all()
  end

  @impl true
  def delete_samples_before(%Date{} = day) do
    {deleted, _rows} = DailySample |> where([s], s.day < ^day) |> Repo.delete_all()
    deleted
  end

  ## Incidents

  @impl true
  def list_incidents(%DateTime{} = since) do
    Incident
    |> where([i], is_nil(i.resolved_at) or i.resolved_at >= ^since)
    |> order_by([i], desc: i.started_at, desc: i.id)
    |> preload(:updates)
    |> Repo.all()
  end

  @impl true
  def get_incident(id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> Incident |> Repo.get(id) |> Repo.preload(:updates)
      :error -> nil
    end
  end

  @impl true
  def create_incident(attrs, update_attrs) do
    Repo.transaction(fn ->
      with {:ok, incident} <- attrs |> Incident.create_changeset() |> Repo.insert(),
           {:ok, update} <-
             update_attrs
             |> Map.put(:incident_id, incident.id)
             |> IncidentUpdate.create_changeset()
             |> Repo.insert() do
        {Repo.preload(incident, :updates), update}
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> unwrap_pair()
  end

  @impl true
  def add_update(id, author_id, fun) do
    with {:ok, id} <- cast_id(id) do
      Repo.transaction(fn ->
        with %Incident{} = incident <- lock_incident(id),
             {:ok, changes} <- fun.(incident),
             {:ok, update} <-
               %{
                 incident_id: incident.id,
                 status: changes.status,
                 body: changes.body,
                 notify: changes.notify,
                 created_by_id: author_id,
                 locale: Map.get(changes, :locale),
                 body_en: Map.get(changes, :body_en),
                 en_source: Map.get(changes, :en_source)
               }
               |> IncidentUpdate.create_changeset()
               |> Repo.insert(),
             {:ok, incident} <-
               incident
               |> Incident.change_changeset(incident_changes(changes))
               |> Repo.update() do
          {incident |> Repo.preload(:updates, force: true), update}
        else
          nil -> Repo.rollback(:status_incident_not_found)
          {:error, reason} -> Repo.rollback(reason)
        end
      end)
      |> unwrap_pair()
    end
  end

  defp incident_changes(changes) do
    %{status: changes.status}
    |> maybe_put(:resolved_at, changes.resolved_at)
    |> maybe_put(:started_at, changes.started_at)
  end

  @impl true
  def edit_incident(id, changes) do
    with {:ok, id} <- cast_id(id) do
      case Repo.get(Incident, id) do
        nil ->
          {:error, :status_incident_not_found}

        incident ->
          with {:ok, incident} <-
                 incident |> Incident.change_changeset(changes) |> Repo.update() do
            {:ok, Repo.preload(incident, :updates)}
          end
      end
    end
  end

  @impl true
  def get_update(id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> Repo.get(IncidentUpdate, id)
      :error -> nil
    end
  end

  defp lock_incident(id),
    do: Incident |> where([i], i.id == ^id) |> lock("FOR UPDATE") |> Repo.one()

  ## Subscribers

  @impl true
  def get_subscriber_by_digest(digest),
    do: Repo.get_by(Subscriber, email_digest: digest)

  @impl true
  def get_subscriber(id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> Repo.get(Subscriber, id)
      :error -> nil
    end
  end

  @impl true
  def create_subscriber(attrs), do: attrs |> Subscriber.create_changeset() |> Repo.insert()

  @impl true
  def refresh_subscriber(%Subscriber{} = subscriber, attrs),
    do: subscriber |> Subscriber.change_changeset(attrs) |> Repo.update(force: true)

  @impl true
  def confirm_subscriber(digest, %DateTime{} = not_before, %DateTime{} = now) do
    query =
      from(s in Subscriber,
        where:
          s.confirm_token_digest == ^digest and is_nil(s.confirmed_at) and
            s.updated_at >= ^not_before,
        select: s
      )

    case Repo.update_all(query,
           set: [confirmed_at: now, confirm_token_digest: nil, updated_at: now]
         ) do
      {1, [subscriber]} -> {:ok, subscriber}
      {0, _rows} -> {:error, :not_found}
    end
  end

  @impl true
  def delete_subscriber(id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} ->
        _deleted = Subscriber |> where([s], s.id == ^id) |> Repo.delete_all()
        :ok

      :error ->
        :ok
    end
  end

  @impl true
  def delete_unconfirmed_before(%DateTime{} = cutoff) do
    {deleted, _rows} =
      Subscriber
      |> where([s], is_nil(s.confirmed_at) and s.updated_at < ^cutoff)
      |> Repo.delete_all()

    deleted
  end

  @impl true
  def list_confirmed_subscribers(after_id, limit) do
    Subscriber
    |> where([s], not is_nil(s.confirmed_at))
    |> after_id(after_id)
    |> order_by([s], asc: s.id)
    |> limit(^limit)
    |> Repo.all()
  end

  @impl true
  def count_subscribers do
    {confirmed, waiting} =
      Subscriber
      |> select([s], {
        filter(count(s.id), not is_nil(s.confirmed_at)),
        filter(count(s.id), is_nil(s.confirmed_at))
      })
      |> Repo.one()

    %{confirmed: confirmed, waiting: waiting}
  end

  defp after_id(query, nil), do: query
  defp after_id(query, id), do: where(query, [s], s.id > ^id)

  ## Helpers

  defp cast_id(id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> {:ok, id}
      :error -> {:error, :status_incident_not_found}
    end
  end

  defp unwrap_pair({:ok, {incident, update}}), do: {:ok, incident, update}
  defp unwrap_pair({:error, _reason} = error), do: error

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp truncate(nil, _max), do: nil
  defp truncate(text, max) when is_binary(text), do: String.slice(text, 0, max)
  defp truncate(other, max), do: other |> inspect() |> truncate(max)
end

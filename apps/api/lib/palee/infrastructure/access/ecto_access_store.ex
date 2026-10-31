defmodule Palee.Infrastructure.Access.EctoAccessStore do
  @moduledoc "Ecto adapter of the door access store (ADR-381)."

  @behaviour Palee.Access.Ports.AccessStore

  import Ecto.Query

  alias Palee.Access.{AccessEvent, DoorController}
  alias Palee.Repo

  @max_page 200

  @impl true
  def lookup_door(id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         {:ok, %{rows: [[organization_id]]}} when not is_nil(organization_id) <-
           Repo.query("SELECT palee_door_controller_lookup($1)", [Ecto.UUID.dump!(id)]) do
      Ecto.UUID.load!(organization_id)
    else
      _missing -> nil
    end
  end

  @impl true
  def list_doors(%{organization_id: organization_id}, filters) do
    DoorController
    |> where([d], d.organization_id == ^organization_id)
    |> maybe_where(:location_id, filters[:location_id])
    |> maybe_where(:status, filters[:status])
    |> order_by([d], asc: d.name, asc: d.inserted_at)
    |> Repo.all()
    |> Enum.map(&door_map/1)
  end

  @impl true
  def get_door(%{organization_id: organization_id}, id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %DoorController{} = door <-
           Repo.one(
             from d in DoorController, where: d.organization_id == ^organization_id and d.id == ^id
           ) do
      door_map(door)
    else
      _missing -> nil
    end
  end

  @impl true
  def insert_door(_context, attrs) do
    %DoorController{}
    |> DoorController.changeset(encode_credentials(attrs))
    |> Repo.insert()
    |> door_result()
  end

  @impl true
  def update_door(%{organization_id: organization_id}, id, changes) do
    query = from d in DoorController, where: d.organization_id == ^organization_id and d.id == ^id

    case Repo.one(query) do
      nil ->
        {:error, :not_found}

      door ->
        door |> DoorController.changeset(encode_credentials(changes)) |> Repo.update() |> door_result()
    end
  end

  @impl true
  def delete_door(%{organization_id: organization_id}, id) do
    DoorController
    |> where([d], d.organization_id == ^organization_id and d.id == ^id)
    |> Repo.delete_all()

    :ok
  end

  @impl true
  def insert_event(_context, attrs) do
    case %AccessEvent{} |> AccessEvent.changeset(attrs) |> Repo.insert() do
      {:ok, event} -> {:ok, plain(event)}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @impl true
  def list_events(%{organization_id: organization_id}, filters) do
    limit = min(filters[:limit] || 50, @max_page)
    offset = filters[:offset] || 0

    query =
      AccessEvent
      |> where([e], e.organization_id == ^organization_id)
      |> maybe_where(:door_controller_id, filters[:door_id])
      |> maybe_where(:location_id, filters[:location_id])
      |> maybe_where(:user_id, filters[:user_id])
      |> maybe_where(:kind, filters[:kind])

    %{
      total: Repo.aggregate(query, :count),
      events:
        query
        |> order_by([e], desc: e.occurred_at)
        |> limit(^limit)
        |> offset(^offset)
        |> Repo.all()
        |> Enum.map(&plain/1)
    }
  end

  @impl true
  def purge_events(%{organization_id: organization_id}, %DateTime{} = before) do
    {count, _rows} =
      AccessEvent
      |> where([e], e.organization_id == ^organization_id and e.occurred_at < ^before)
      |> Repo.delete_all()

    count
  end

  defp encode_credentials(%{credentials: map} = attrs) when is_map(map),
    do: %{attrs | credentials: Jason.encode!(map)}

  defp encode_credentials(attrs), do: attrs

  defp maybe_where(query, _field, nil), do: query
  defp maybe_where(query, field, value), do: where(query, [row], field(row, ^field) == ^value)

  defp door_result({:ok, door}), do: {:ok, door_map(door)}
  defp door_result({:error, _reason} = error), do: error

  defp door_map(%DoorController{} = door) do
    credentials =
      case door.credentials && Jason.decode(door.credentials) do
        {:ok, map} when is_map(map) -> map
        _missing -> %{}
      end

    door |> plain() |> Map.put(:credentials, credentials)
  end

  defp plain(%_{} = struct), do: struct |> Map.from_struct() |> Map.delete(:__meta__)
end

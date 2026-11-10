defmodule Palee.Infrastructure.Organizations.EctoJoinRequestStore do
  @moduledoc "ADR-552: «Ζήτα να γίνεις μέλος» requests in Postgres (RLS by box; the person reads their own)."

  @behaviour Palee.Organizations.Ports.JoinRequestStore

  import Ecto.Query

  alias Palee.Infrastructure.Tenancy.RepoContext
  alias Palee.Organizations.JoinRequest
  alias Palee.Repo

  @impl true
  def ask(user_id) do
    Repo.transaction(fn ->
      case open_for(user_id) do
        %JoinRequest{} = existing ->
          {normalize(existing), :existing}

        nil ->
          %{user_id: user_id}
          |> JoinRequest.create_changeset()
          |> Repo.insert()
          |> case do
            {:ok, request} -> {normalize(request), :created}
            # Two presses at once: the unique index refuses the second insert.
            {:error, _changeset} -> {normalize(open_for(user_id)), :existing}
          end
      end
    end)
    |> case do
      {:ok, {nil, _how}} -> {:error, :join_request_conflict}
      {:ok, {request, how}} -> {:ok, request, how}
      {:error, reason} -> {:error, reason}
    end
  end

  defp open_for(user_id) do
    JoinRequest
    |> box_scope()
    |> where([r], r.user_id == ^user_id and r.status == "requested")
    |> Repo.one()
  end

  @impl true
  def get(id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} ->
        JoinRequest |> box_scope() |> where([r], r.id == ^id) |> Repo.one() |> normalize()

      :error ->
        nil
    end
  end

  @impl true
  def latest_for(user_id) do
    JoinRequest
    |> box_scope()
    |> where([r], r.user_id == ^user_id)
    |> order_by([r], desc: r.inserted_at, desc: r.id)
    |> limit(1)
    |> Repo.one()
    |> normalize()
  end

  @impl true
  def list_open do
    JoinRequest
    |> box_scope()
    |> where([r], r.status == "requested")
    |> order_by([r], asc: r.inserted_at, asc: r.id)
    |> Repo.all()
    |> Enum.map(&normalize/1)
  end

  # The person's own requests across boxes: the owner-read policy lets them
  # see their rows whatever box they are at, so there is no box scope here.
  @impl true
  def open_organization_ids(_user_id, []), do: []

  def open_organization_ids(user_id, organization_ids) do
    JoinRequest
    |> where(
      [r],
      r.user_id == ^user_id and r.status == "requested" and r.organization_id in ^organization_ids
    )
    |> select([r], r.organization_id)
    |> distinct(true)
    |> Repo.all()
  end

  @impl true
  def close(id, params) do
    Repo.transaction(fn ->
      with {:ok, id} <- Ecto.UUID.cast(id),
           %JoinRequest{} = request <- locked(id) do
        if request.status == "requested" do
          request
          |> JoinRequest.close_changeset(params)
          |> Repo.update()
          |> case do
            {:ok, closed} -> normalize(closed)
            {:error, changeset} -> Repo.rollback(changeset)
          end
        else
          Repo.rollback(:join_request_closed)
        end
      else
        _ -> Repo.rollback(:not_found)
      end
    end)
  end

  defp locked(id) do
    JoinRequest
    |> box_scope()
    |> where([r], r.id == ^id)
    |> lock("FOR UPDATE")
    |> Repo.one()
  end

  defp box_scope(queryable) do
    case RepoContext.current_setting("app.organization_id") do
      organization_id when is_binary(organization_id) and organization_id != "" ->
        from(row in queryable, where: field(row, :organization_id) == ^organization_id)

      _ ->
        from(row in queryable, where: false)
    end
  end

  defp normalize(nil), do: nil

  defp normalize(%JoinRequest{} = request),
    do: request |> Map.from_struct() |> Map.drop([:__meta__])
end

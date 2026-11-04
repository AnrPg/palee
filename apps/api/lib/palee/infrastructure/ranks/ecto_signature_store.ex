defmodule Palee.Infrastructure.Ranks.EctoSignatureStore do
  @moduledoc "Ecto adapter of the diploma signature port (ADR-377 addendum)."

  @behaviour Palee.Ranks.Ports.SignatureStore

  import Ecto.Query

  alias Palee.Ranks.{DiplomaSignature, DiplomaSignatureEvent}
  alias Palee.Repo

  @impl true
  def current(user_id) do
    DiplomaSignature
    |> where([s], s.user_id == ^user_id and is_nil(s.retired_at))
    |> Repo.one()
  end

  @impl true
  def get(id), do: Repo.get(DiplomaSignature, id)

  @impl true
  def list(user_id) do
    DiplomaSignature
    |> where([s], s.user_id == ^user_id)
    |> order_by([s], asc: s.inserted_at)
    |> Repo.all()
  end

  @impl true
  def replace(user_id, attrs, now) do
    Repo.transaction(fn ->
      DiplomaSignature
      |> where([s], s.user_id == ^user_id and is_nil(s.retired_at))
      |> Repo.update_all(set: [retired_at: now, updated_at: now])

      with {:ok, signature} <-
             attrs |> Map.put(:user_id, user_id) |> DiplomaSignature.changeset() |> Repo.insert(),
           {:ok, _event} <- event(user_id, "set", signature, now) do
        signature
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @impl true
  def remove(user_id, now) do
    Repo.transaction(fn ->
      {_count, removed} =
        DiplomaSignature
        |> where([s], s.user_id == ^user_id)
        |> select([s], s)
        |> Repo.delete_all()

      case removed != [] && event(user_id, "removed", nil, now) do
        {:error, reason} -> Repo.rollback(reason)
        _recorded -> removed
      end
    end)
  end

  @impl true
  def events(user_id) do
    DiplomaSignatureEvent
    |> where([e], e.user_id == ^user_id)
    |> order_by([e], desc: e.occurred_at)
    |> Repo.all()
  end

  defp event(user_id, action, signature, now) do
    %{
      user_id: user_id,
      action: action,
      signature_id: signature && signature.id,
      sha256: signature && signature.sha256,
      occurred_at: now
    }
    |> DiplomaSignatureEvent.changeset()
    |> Repo.insert()
  end
end

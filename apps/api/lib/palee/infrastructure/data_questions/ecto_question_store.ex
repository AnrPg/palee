defmodule Palee.Infrastructure.DataQuestions.EctoQuestionStore do
  @moduledoc "Ecto adapter of `DataQuestions.Ports.QuestionStore` (ADR-361)."

  @behaviour Palee.DataQuestions.Ports.QuestionStore

  import Ecto.Query

  alias Palee.DataQuestions.DataQuestion
  alias Palee.Repo

  @impl true
  def insert(%{organization_id: organization_id}, attrs) do
    organization_id |> DataQuestion.changeset(attrs) |> Repo.insert()
  end

  @impl true
  def get(%{organization_id: organization_id}, id) do
    DataQuestion
    |> where([q], q.organization_id == ^organization_id and q.id == ^id)
    |> Repo.one()
  end

  @impl true
  def list(%{organization_id: organization_id}, filters) do
    DataQuestion
    |> where([q], q.organization_id == ^organization_id)
    |> filter(filters)
    |> order_by([q], desc: q.inserted_at)
    |> limit(^Map.get(filters, :limit, 30))
    |> Repo.all()
  end

  @impl true
  def count_since(%{organization_id: organization_id}, user_id, since) do
    DataQuestion
    |> where(
      [q],
      q.organization_id == ^organization_id and q.user_id == ^user_id and
        q.inserted_at >= ^since and q.status != "refused"
    )
    |> select([q], count(q.id))
    |> Repo.one()
  end

  defp filter(query, filters) do
    Enum.reduce(filters, query, fn
      {:user_id, user_id}, query when is_binary(user_id) -> where(query, [q], q.user_id == ^user_id)
      {:before, %DateTime{} = before}, query -> where(query, [q], q.inserted_at < ^before)
      _other, query -> query
    end)
  end
end

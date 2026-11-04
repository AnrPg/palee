defmodule Palee.Infrastructure.Search.PostgresExerciseNameIndex do
  @moduledoc """
  ADR-461: exercise-name suggestions straight from Postgres. Remembered
  names live in `exercise_names` (row-level security per owner); a search
  prefilters them with `strpos` and pg_trgm `word_similarity` on the folded
  key, and ranks them, and the in-memory Palee catalog, with the same
  typo-tolerant rules the web uses (`ExerciseNames.rank/3`). The adapter in
  test, and the Meilisearch adapter's fallback when Meilisearch is down.
  """

  @behaviour Palee.Application.Ports.ExerciseNameIndex

  import Ecto.Query

  alias Palee.Infrastructure.Tenancy.RepoContext
  alias Palee.Repo
  alias Palee.Workers.RecordExerciseNamesJob
  alias Palee.Workouts.Domain.ExerciseNames
  alias Palee.Workouts.ExerciseName

  @candidates 300
  @similarity 0.3

  @impl true
  def enqueue_record(owner, rows, increment) do
    case job_rows(rows) do
      [] ->
        :ok

      rows ->
        owner
        |> RecordExerciseNamesJob.args(rows, increment)
        |> RecordExerciseNamesJob.new()
        |> Repo.insert()
        |> case do
          {:ok, _job} -> :ok
          {:error, reason} -> {:error, reason}
        end
    end
  end

  @impl true
  def record(owner, entries, increment) do
    case upsert(owner, entries, increment) do
      {:ok, %{new: new}} -> {:ok, new}
      error -> error
    end
  end

  @doc """
  Upserts the owner's entries (`%{name, folded, catalog_slug}`, already
  cleaned); returns the saved rows and the folded keys the owner had not
  typed before.
  """
  def upsert(owner, entries, increment) do
    case Enum.filter(entries, &valid_entry?/1) do
      [] ->
        {:ok, %{saved: [], new: []}}

      entries ->
        now = DateTime.utc_now()
        folded = Enum.map(entries, & &1.folded)

        placeholders =
          Enum.map(entries, fn entry ->
            entry
            |> Map.take([:name, :folded, :catalog_slug])
            |> Map.merge(owner_fields(owner))
            |> Map.merge(%{
              id: Ecto.UUID.generate(),
              uses_count: 1,
              last_used_at: now,
              inserted_at: now,
              updated_at: now
            })
          end)

        RepoContext.run(repo_context(owner), fn ->
          known =
            Repo.all(
              from(n in ExerciseName,
                where: ^owner_filter(owner),
                where: n.folded in ^folded,
                select: n.folded
              )
            )

          {_count, saved} =
            Repo.insert_all(ExerciseName, placeholders,
              on_conflict: on_conflict(increment),
              conflict_target: conflict_target(owner),
              returning: true
            )

          {:ok, %{saved: saved, new: folded -- known}}
        end)
    end
  end

  defp valid_entry?(%{name: name, folded: folded} = entry)
       when is_binary(name) and is_binary(folded) and name != "" and folded != "",
       do: is_nil(entry[:catalog_slug]) or is_binary(entry[:catalog_slug])

  defp valid_entry?(_entry), do: false

  @impl true
  def search(viewer, query, limit, catalog) do
    with {:ok, rows} <- candidates(viewer, query) do
      {:ok, rank(query, rows, limit, catalog)}
    end
  end

  @doc "Ranks remembered rows and the catalog for the query, per source."
  def rank(query, rows, limit, catalog) do
    {mine, box} = Enum.split_with(rows, &(&1.scope == "user"))
    take = limit + 5

    %{
      mine: query |> ExerciseNames.rank(Enum.map(mine, &hit/1), take),
      box: query |> ExerciseNames.rank(Enum.map(box, &hit/1), take),
      palee: catalog_hits(query, take, catalog)
    }
  end

  @doc "The Palee catalog ranked for the query."
  def catalog_hits(query, limit, catalog) do
    query
    |> ExerciseNames.rank(catalog, limit)
    |> Enum.map(&Map.take(&1, [:name, :catalog_slug, :category]))
  end

  @impl true
  def rebuild(_owners, _catalog), do: {:ok, 0}

  @impl true
  def refresh_catalog(_catalog), do: :ok

  @doc "The remembered names of `owners` (the Meilisearch rebuild's source), each read in its owner's scope."
  def owner_rows(owners) when is_list(owners), do: Enum.flat_map(owners, &rows_of/1)

  defp rows_of(owner) do
    RepoContext.run(repo_context(owner), fn ->
      Repo.all(from(n in ExerciseName, where: ^owner_filter(owner)))
    end)
  end

  defp candidates(viewer, query) do
    case ExerciseNames.query_words(query) do
      [] ->
        {:ok, []}

      words ->
        context = %{user_id: viewer.user_id, organization_id: viewer[:organization_id]}

        RepoContext.run(viewer_context(context), fn ->
          {:ok,
           Repo.all(
             from(n in ExerciseName,
               where: ^viewer_filter(context),
               where:
                 fragment(
                   "EXISTS (SELECT 1 FROM unnest(?::text[]) AS w WHERE strpos(?, w) > 0 OR (char_length(w) >= 3 AND word_similarity(w, ?) >= ?))",
                   ^words,
                   n.folded,
                   n.folded,
                   ^@similarity
                 ),
               order_by: [desc: n.uses_count, desc: n.last_used_at],
               limit: @candidates
             )
           )}
        end)
    end
  end

  defp viewer_filter(%{user_id: user_id, organization_id: organization_id})
       when is_binary(organization_id),
       do:
         dynamic(
           [n],
           (n.scope == "user" and n.user_id == ^user_id) or
             (n.scope == "org" and n.organization_id == ^organization_id)
         )

  defp viewer_filter(%{user_id: user_id}),
    do: dynamic([n], n.scope == "user" and n.user_id == ^user_id)

  defp viewer_context(%{organization_id: organization_id} = context)
       when is_binary(organization_id),
       do: context

  defp viewer_context(context), do: Map.delete(context, :organization_id)

  defp owner_filter(%{scope: :user, user_id: user_id}),
    do: dynamic([n], n.scope == "user" and n.user_id == ^user_id)

  defp owner_filter(%{scope: :org, organization_id: organization_id}),
    do: dynamic([n], n.scope == "org" and n.organization_id == ^organization_id)

  defp hit(row),
    do: %{
      id: row.id,
      name: row.name,
      catalog_slug: row.catalog_slug,
      uses_count: row.uses_count,
      aliases: []
    }

  defp owner_fields(%{scope: :user, user_id: user_id}),
    do: %{scope: "user", user_id: user_id, organization_id: nil}

  defp owner_fields(%{scope: :org, organization_id: organization_id}),
    do: %{scope: "org", user_id: nil, organization_id: organization_id}

  defp repo_context(%{scope: :user, user_id: user_id}), do: %{user_id: user_id}

  defp repo_context(%{scope: :org, organization_id: organization_id}),
    do: %{organization_id: organization_id}

  defp conflict_target(%{scope: :user}),
    do: {:unsafe_fragment, "(user_id, folded) WHERE scope = 'user'"}

  defp conflict_target(%{scope: :org}),
    do: {:unsafe_fragment, "(organization_id, folded) WHERE scope = 'org'"}

  defp on_conflict(increment) do
    from(n in ExerciseName,
      update: [
        inc: [uses_count: ^increment],
        set: [
          name: fragment("EXCLUDED.name"),
          catalog_slug: fragment("COALESCE(EXCLUDED.catalog_slug, ?)", n.catalog_slug),
          last_used_at: fragment("EXCLUDED.last_used_at"),
          updated_at: fragment("EXCLUDED.updated_at")
        ]
      ]
    )
  end

  # Names cleaned for the job; a given slug travels as given (the job checks
  # it against the catalog with its additions).
  defp job_rows(rows) when is_list(rows) do
    rows
    |> Enum.flat_map(fn
      row when is_map(row) ->
        name = ExerciseNames.clean_name(Map.get(row, :name) || Map.get(row, "name"))

        slug =
          Map.get(row, :catalog_slug) || Map.get(row, "catalog_slug") ||
            Map.get(row, :exercise_ref) || Map.get(row, "exercise_ref")

        if name,
          do: [
            %{
              "name" => name,
              "catalog_slug" => if(is_binary(slug), do: String.slice(slug, 0, 120))
            }
          ],
          else: []

      _other ->
        []
    end)
    |> Enum.uniq_by(&ExerciseNames.fold(&1["name"]))
  end

  defp job_rows(_rows), do: []
end

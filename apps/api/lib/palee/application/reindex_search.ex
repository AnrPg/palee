defmodule Palee.Application.ReindexSearch do
  @moduledoc """
  Rebuilds every Meilisearch index from Postgres: the admin member index,
  the per-member PR index and the exercise-name suggestions (ADR-461: the
  Palee catalog, each member's own names and each box's). Run after the search store is replaced or emptied
  (`Palee.Release.reindex_search/0`). PRs are owner-only under RLS, so each
  member's are read in that member's scope.
  """

  alias Palee.Application.{
    AdminMemberSearchDocuments,
    AdminMemberSearchIndex,
    ExerciseNameIndex,
    PRSearchIndex
  }

  alias Palee.{Identity, Organizations, Pantheon, Workouts}

  def call do
    users = Identity.list_all_users()
    prs = Enum.flat_map(users, &user_prs/1)

    with :ok <- AdminMemberSearchIndex.replace_documents(AdminMemberSearchDocuments.build_all()),
         :ok <- PRSearchIndex.replace_documents(Enum.map(prs, &document/1)),
         {:ok, exercise_names} <-
           ExerciseNameIndex.rebuild(
             exercise_name_owners(users),
             Workouts.exercise_catalog_documents()
           ) do
      {:ok, %{prs: length(prs), exercise_names: exercise_names}}
    end
  end

  defp exercise_name_owners(users) do
    user_ids = Enum.map(users, & &1.id)

    organization_ids =
      user_ids
      |> Organizations.list_membership_organization_ids()
      |> Map.values()
      |> List.flatten()
      |> Enum.uniq()

    Enum.map(user_ids, &%{scope: :user, user_id: &1}) ++
      Enum.map(organization_ids, &%{scope: :org, organization_id: &1})
  end

  defp user_prs(%{id: user_id}),
    do: Pantheon.with_user_context(%{user_id: user_id}, fn -> Pantheon.list_records(user_id) end)

  defp document(pr), do: %{id: pr.id, user_id: pr.user_id, name: pr.name}
end

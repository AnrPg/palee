defmodule Palee.Application.SuggestExerciseNames do
  @moduledoc """
  ADR-461: suggestions for an exercise name being typed, for any signed-in
  person. Groups, in order: «Έχεις γράψει» (`mine`, the person's own
  names), «Του box σου» (`box`, the names of the given box's published WODs,
  only when the person belongs to that box), «Palee» (`palee`, the catalog
  with aliases). A name shows once. The typed text is never replaced here:
  the web offers keeping it as typed.
  """

  alias Palee.Application.ExerciseNameIndex
  alias Palee.{Organizations, Workouts}

  @default_limit 5
  @max_limit 10
  @max_query 80

  def call(%{user_id: user_id} = context, params) when is_binary(user_id) and is_map(params) do
    query = query(params["q"])
    limit = limit(params["limit"])

    if query == "" do
      {:ok, %{groups: []}}
    else
      viewer = %{user_id: user_id, organization_id: organization_id(context, params)}
      catalog = Workouts.exercise_catalog_documents()

      with {:ok, hits} <- ExerciseNameIndex.search(viewer, query, limit, catalog) do
        groups =
          hits
          |> Workouts.group_exercise_suggestions(limit)
          |> Enum.map(&present_group(&1, catalog))

        {:ok, %{groups: groups}}
      end
    end
  end

  def call(_context, _params), do: {:error, :unauthorized}

  defp present_group(%{source: source, items: items}, catalog),
    do: %{source: Atom.to_string(source), items: Enum.map(items, &present_item(&1, catalog))}

  defp present_item(item, catalog) do
    %{
      name: item.name,
      catalog_slug:
        if(Workouts.exercise_catalog_slug?(item.catalog_slug, catalog), do: item.catalog_slug),
      hint: item.hint,
      uses_count: item.uses_count
    }
  end

  # The box's names only for one of its active members (or staff).
  defp organization_id(%{account: account}, %{"organization_id" => id}) when is_binary(id) do
    with {:ok, uuid} <- Ecto.UUID.cast(id),
         {:ok, %{organization_id: organization_id}} <-
           Organizations.resolve_tenant_context_by_id(account, uuid) do
      organization_id
    else
      _not_member -> nil
    end
  end

  defp organization_id(_context, _params), do: nil

  defp query(q) when is_binary(q), do: q |> String.trim() |> String.slice(0, @max_query)
  defp query(_q), do: ""

  defp limit(value) when is_integer(value), do: value |> max(1) |> min(@max_limit)

  defp limit(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} -> limit(n)
      _invalid -> @default_limit
    end
  end

  defp limit(_value), do: @default_limit
end

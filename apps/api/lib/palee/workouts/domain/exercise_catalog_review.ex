defmodule Palee.Workouts.Domain.ExerciseCatalogReview do
  @moduledoc """
  ADR-461: the verified way the WOD editors' exercise catalog grows. A
  candidate (a typed name that matched nothing) is approved by the Palee
  team as a new entry or as an alias of an existing entry, or rejected.
  Pure: checks a decision against the candidate and the current catalog
  documents and says what to write.
  """

  alias Palee.Workouts.Domain.ExerciseNames

  @categories ~w(strength bodyweight cardio mobility skill)
  @decisions ~w(entry alias reject)

  def categories, do: @categories
  def decisions, do: @decisions

  @doc """
  `params` (string keys): `decision` (`entry`, `alias`, `reject`); for
  `entry` a `category` and optionally a `label` (default: the candidate's
  name); for `alias` the entry's `catalog_slug` and optionally the alias
  `label`. Returns `{:ok, %{action, addition}}` with `addition` the
  `exercise_catalog_additions` attributes (or `nil` for a rejection).
  """
  def decide(%{status: "pending"} = candidate, params, docs) when is_map(params) do
    case params["decision"] do
      "entry" -> new_entry(candidate, params, docs)
      "alias" -> new_alias(candidate, params, docs)
      "reject" -> {:ok, %{action: "reject", addition: nil, catalog_slug: nil}}
      _other -> {:error, :invalid_exercise_catalog_decision}
    end
  end

  def decide(%{status: _decided}, _params, _docs),
    do: {:error, :exercise_candidate_already_decided}

  defp new_entry(candidate, params, docs) do
    label = label(params, candidate)
    slug = slugify(label)

    cond do
      label == nil or slug == "" ->
        {:error, :invalid_exercise_label}

      params["category"] not in @categories ->
        {:error, :invalid_exercise_category}

      Enum.any?(docs, &(&1.catalog_slug == slug)) ->
        {:error, :exercise_catalog_slug_taken}

      ExerciseNames.resolve_slug(label, docs) != nil ->
        {:error, :exercise_already_in_catalog}

      true ->
        {:ok,
         %{
           action: "approve_entry",
           catalog_slug: slug,
           addition: %{
             kind: "entry",
             catalog_slug: slug,
             label: label,
             folded: ExerciseNames.fold(label),
             category: params["category"]
           }
         }}
    end
  end

  defp new_alias(candidate, params, docs) do
    label = label(params, candidate)
    slug = params["catalog_slug"]

    cond do
      label == nil ->
        {:error, :invalid_exercise_label}

      not Enum.any?(docs, &(&1.catalog_slug == slug)) ->
        {:error, :unknown_exercise_catalog_slug}

      ExerciseNames.resolve_slug(label, docs) != nil ->
        {:error, :exercise_already_in_catalog}

      true ->
        {:ok,
         %{
           action: "approve_alias",
           catalog_slug: slug,
           addition: %{
             kind: "alias",
             catalog_slug: slug,
             label: label,
             folded: ExerciseNames.fold(label),
             category: nil
           }
         }}
    end
  end

  defp label(params, candidate) do
    case params["label"] do
      label when is_binary(label) -> ExerciseNames.clean_name(label)
      _none -> ExerciseNames.clean_name(candidate.name)
    end
  end

  @doc "A stable slug for a new entry's label: Latin letters and digits, dash-separated."
  def slugify(label) when is_binary(label) do
    label
    |> ExerciseNames.fold()
    |> Palee.Transliteration.latin()
    |> String.replace("&", " and ")
    |> String.replace(~r/[^a-z0-9]+/u, "-")
    |> String.trim("-")
    |> String.slice(0, 80)
  end

  def slugify(_label), do: ""
end

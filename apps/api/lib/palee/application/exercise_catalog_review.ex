defmodule Palee.Application.ExerciseCatalogReview do
  @moduledoc """
  ADR-461: the Palee team grows the WOD editors' exercise catalog from what
  people type (vendor console «Ασκήσεις προς έλεγχο»). The queue lists the
  typed names that matched no entry, counted and deduplicated by folded
  form; by default only names at least two owners typed (a name one person
  typed may be personal, and stays theirs). A decision approves a name as a
  new entry or as an alias of an existing entry, or rejects it; it is
  written with its audit event, and an approval refreshes the «Palee»
  scope of the search index at once.

  ADR-560: the catalog lives in reference tables. A new entry may come with
  the muscles it trains (by role: primary, secondary, stabilizer) and the
  qualities it develops, and the team can edit any exercise's targets later
  (audited). After each write this pod reloads its catalog copy at once; the
  other pods do so within one revision poll. WOD goals are suggested from
  these targets, and the coach can change them (ADR-163).
  """

  alias Palee.Anatomy
  alias Palee.Application.ExerciseNameIndex
  alias Palee.Catalog
  alias Palee.Organizations.PlatformContext
  alias Palee.Workouts

  @statuses ~w(pending approved rejected)
  @default_min_owners 2
  @limit 200

  def queue(%PlatformContext{}, params) do
    status = if params["status"] in @statuses, do: params["status"], else: "pending"
    min_owners = min_owners(params["min_owners"])

    {:ok,
     %{
       candidates:
         status
         |> Workouts.list_exercise_name_candidates(min_owners, @limit)
         |> Enum.map(&present_candidate/1),
       catalog:
         Enum.map(
           Workouts.exercise_catalog_documents(),
           &Map.take(&1, [:catalog_slug, :name, :category])
         )
     }}
  end

  def queue(_context, _params), do: {:error, :vendor_required}

  def decide(context, candidate_id, params, now \\ nil)

  def decide(%PlatformContext{user_id: vendor_id}, candidate_id, params, now) do
    now = now || DateTime.utc_now()
    params = stringify(params)

    with {:ok, targets} <- targets(params, :optional),
         {:ok, %{candidate: candidate, addition: addition}} <-
           Workouts.decide_exercise_name_candidate(candidate_id, params, targets, vendor_id, now) do
      if addition, do: catalog_changed()
      {:ok, %{candidate: present_candidate(candidate)}}
    end
  end

  def decide(_context, _candidate_id, _params, _now), do: {:error, :vendor_required}

  @doc "ADR-560: every catalog exercise with its aliases and targets (vendor console)."
  def exercises(%PlatformContext{}) do
    {:ok, %{exercises: Enum.map(Workouts.exercise_catalog_entries(), &present_exercise/1)}}
  end

  def exercises(_context), do: {:error, :vendor_required}

  @doc "ADR-560: replaces an exercise's muscles (by role) and qualities, audited."
  def set_targets(context, exercise_id, params, now \\ nil)

  def set_targets(%PlatformContext{user_id: vendor_id}, exercise_id, params, now) do
    now = now || DateTime.utc_now()

    with {:ok, targets} <- targets(stringify(params), :required),
         {:ok, _result} <- Workouts.replace_exercise_targets(exercise_id, targets, vendor_id, now) do
      catalog_changed()
      {:ok, %{exercise: exercise_id |> Workouts.exercise_catalog_entry() |> present_exercise()}}
    end
  end

  def set_targets(_context, _exercise_id, _params, _now), do: {:error, :vendor_required}

  # Targets are validated like WOD goals (known groups and heads, the three
  # roles, known qualities); a muscle named twice keeps its strongest role.
  defp targets(params, mode) do
    given? = Map.has_key?(params, "muscles") or Map.has_key?(params, "qualities")

    if not given? and mode == :optional do
      {:ok, nil}
    else
      with {:ok, goals} <-
             Anatomy.normalize_goals(%{
               "muscles" => Map.get(params, "muscles") || [],
               "qualities" => Map.get(params, "qualities") || []
             }),
           do: {:ok, Map.take(goals, [:muscles, :qualities])}
    end
  end

  defp catalog_changed do
    Catalog.refresh()
    ExerciseNameIndex.refresh_catalog(Workouts.exercise_catalog_documents())
  end

  defp present_exercise(exercise) do
    targets = Anatomy.exercise_targets(exercise.id) || %{muscles: [], qualities: []}

    %{
      id: exercise.id,
      label: exercise.label,
      category: exercise.category,
      origin: exercise.origin,
      aliases: exercise.aliases,
      search_aliases: Workouts.exercise_catalog_search_aliases(exercise.id),
      muscles: Enum.map(targets.muscles, &%{id: &1.id, role: Atom.to_string(&1.role)}),
      qualities: targets.qualities
    }
  end

  def audit(%PlatformContext{}) do
    {:ok,
     %{
       events:
         Enum.map(Workouts.exercise_catalog_audit_events(@limit), fn event ->
           %{
             id: event.id,
             action: event.action,
             actor_user_id: event.actor_user_id,
             candidate_id: event.candidate_id,
             catalog_slug: event.catalog_slug,
             metadata: event.metadata,
             at: event.inserted_at
           }
         end)
     }}
  end

  def audit(_context), do: {:error, :vendor_required}

  defp present_candidate(candidate) do
    %{
      id: candidate.id,
      name: candidate.name,
      uses_count: candidate.uses_count,
      owners_count: candidate.owners_count,
      status: candidate.status,
      catalog_slug: candidate.catalog_slug,
      first_seen_at: candidate.first_seen_at,
      last_seen_at: candidate.last_seen_at,
      decided_at: candidate.decided_at
    }
  end

  defp min_owners(value) when is_integer(value) and value >= 1, do: value

  defp min_owners(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} when n >= 1 -> n
      _invalid -> @default_min_owners
    end
  end

  defp min_owners(_value), do: @default_min_owners

  defp stringify(params) when is_map(params),
    do: Map.new(params, fn {key, value} -> {to_string(key), value} end)
end

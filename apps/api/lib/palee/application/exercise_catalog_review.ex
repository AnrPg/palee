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
  """

  alias Palee.Application.ExerciseNameIndex
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

    with {:ok, %{candidate: candidate, addition: addition}} <-
           Workouts.decide_exercise_name_candidate(
             candidate_id,
             stringify(params),
             vendor_id,
             now
           ) do
      if addition, do: ExerciseNameIndex.refresh_catalog(Workouts.exercise_catalog_documents())
      {:ok, %{candidate: present_candidate(candidate)}}
    end
  end

  def decide(_context, _candidate_id, _params, _now), do: {:error, :vendor_required}

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

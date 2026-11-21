defmodule Palee.Application.WorkoutKinds do
  @moduledoc """
  ADR-690: a box's own workout types and the Palee team's queue.

    * Any staff member who writes WODs adds a type from the picker
      (`create/2`); it joins the box's list at once and the name enters the
      Palee team's queue from its first box.
    * Owners and admins rename a type, change its family, hide it or merge
      it into another type (`update/3`, `merge/3`); a merge rewrites the
      box's WODs.
    * The Palee team decides a name (`decide/4`): a new kind for everyone,
      the same as an existing kind, or kept for the boxes. A rewrite runs per
      box in that box's own tenant context (`ApplyWorkoutKindDecisionJob`)
      and tells its owners.
    * Once a day the team gets one email with the names that arrived
      (`send_digest/1`); none on a day without news.

  The public page's «Πρότεινέ το» disciplines share the queue: a name is
  one row whichever way it came.
  """

  require Logger

  alias Palee.{Email, Notifications, Organizations}
  alias Palee.Application.{PublicURL, SuggestBoxTag}
  alias Palee.Workers.ApplyWorkoutKindDecisionJob
  alias Palee.Workouts.Domain.{WorkoutKinds, WorkoutType}
  alias Palee.Workouts.WorkoutKindStore

  @locales ~w(en el de es fr it nl pt_PT ru bg ar he)

  def locales, do: @locales

  # --- The box ---

  @doc "The box's view of every kind (`%{additions, box}`), for its editors."
  def catalogue(context), do: WorkoutKindStore.catalogue(context)

  @doc """
  Adds a type to the box (`%{"label", "family"}`). A name the box already
  has (folded) answers that type, shown again if it was hidden.
  """
  def create(context, params, now \\ DateTime.utc_now()) do
    with :ok <- Organizations.authorize_capability(context, :manage_workouts),
         {:ok, label} <- WorkoutKinds.label(field(params, :label)),
         {:ok, family} <- family(field(params, :family)) do
      folded = WorkoutKinds.fold(label)

      case WorkoutKindStore.find_box_kind_by_folded(context, folded) do
        %{status: "hidden", id: id} ->
          WorkoutKindStore.update_box_kind(context, id, %{status: "active"})

        %{} = existing ->
          {:ok, existing}

        nil ->
          insert(context, label, folded, family, now)
      end
    end
  end

  defp insert(context, label, folded, family, now) do
    attrs = %{label: label, folded: folded, family: family, created_by_id: context.user_id}

    with {:ok, kind} <- WorkoutKindStore.insert_box_kind(context, attrs) do
      note_candidate(kind, context.organization_id, now)
      {:ok, kind}
    end
  end

  # The queue must never fail the coach's save.
  defp note_candidate(kind, organization_id, now) do
    case WorkoutKindStore.note_box_kind_candidate(kind, organization_id, now) do
      {:ok, _candidate} ->
        :ok

      {:error, reason} ->
        Logger.warning("workout_kind_candidate not noted: #{inspect(reason)}")
        :ok
    end
  end

  @doc "Renames a box type, changes its family or hides/shows it (owners and admins)."
  def update(context, id, params) do
    with :ok <- Organizations.authorize_capability(context, :manage_settings),
         %{status: status} = kind when status != "merged" <-
           WorkoutKindStore.get_box_kind(context, id) || {:error, :not_found},
         {:ok, changes} <- changes(kind, params) do
      case WorkoutKindStore.update_box_kind(context, id, changes) do
        {:ok, updated} ->
          if Map.has_key?(changes, :family),
            do: WorkoutKindStore.refresh_box_kind(context, id)

          {:ok, updated}

        error ->
          error
      end
    else
      %{status: "merged"} -> {:error, :not_found}
      error -> error
    end
  end

  defp changes(kind, params) do
    with {:ok, label_changes} <- label_changes(kind, field(params, :label)),
         {:ok, family_changes} <- family_changes(kind, field(params, :family)),
         {:ok, status_changes} <- status_changes(field(params, :hidden)) do
      {:ok, label_changes |> Map.merge(family_changes) |> Map.merge(status_changes)}
    end
  end

  defp label_changes(_kind, nil), do: {:ok, %{}}

  defp label_changes(kind, value) do
    with {:ok, label} <- WorkoutKinds.label(value) do
      if label == kind.label,
        do: {:ok, %{}},
        else: {:ok, %{label: label, folded: WorkoutKinds.fold(label)}}
    end
  end

  defp family_changes(_kind, nil), do: {:ok, %{}}

  defp family_changes(kind, value) do
    with {:ok, family} <- family(value) do
      if family == kind.family, do: {:ok, %{}}, else: {:ok, %{family: family}}
    end
  end

  defp status_changes(nil), do: {:ok, %{}}
  defp status_changes(true), do: {:ok, %{status: "hidden"}}
  defp status_changes(false), do: {:ok, %{status: "active"}}
  defp status_changes(_value), do: {:error, :invalid_workout_kind}

  @doc """
  Merges a box type into another type (a Palee kind or another of the box's
  types): the box's WODs move to it and the merged type leaves the list.
  """
  def merge(context, id, target_ref) do
    with :ok <- Organizations.authorize_capability(context, :manage_settings),
         %{status: status, ref: ref} when status != "merged" <-
           WorkoutKindStore.get_box_kind(context, id) || {:error, :not_found},
         catalogue = WorkoutKindStore.catalogue(context),
         true <-
           (is_binary(target_ref) and target_ref != ref and
              WorkoutKinds.valid?(target_ref, catalogue, [target_ref])) ||
             {:error, :invalid_workout_kind} do
      WorkoutKindStore.merge_box_kind(context, id, target_ref)
    else
      %{status: "merged"} -> {:error, :not_found}
      error -> error
    end
  end

  # --- The Palee team ---

  @doc """
  The queue: pending names (box types and the public page's discipline
  suggestions, one row per name) and the latest decisions.
  """
  def queue(now \\ DateTime.utc_now()) do
    sync_profile_suggestions(now)

    %{
      pending: WorkoutKindStore.list_candidates("pending", 200),
      decided: WorkoutKindStore.recently_decided(50)
    }
  end

  @doc "Every addition (key, family, labels), for every reader."
  def additions, do: WorkoutKindStore.additions()

  @doc """
  What a reader needs to name `refs` from any box: every addition and the
  box types among `refs` (label and family). At most 200 references.
  """
  def lookup(refs) when is_list(refs) do
    ids = refs |> Enum.take(200) |> Enum.map(&WorkoutKinds.box_id/1) |> Enum.reject(&is_nil/1)
    box = WorkoutKindStore.box_kinds_by_ids(Enum.uniq(ids))

    # A merged type also names its target, when that is another box type.
    targets =
      box
      |> Enum.map(&WorkoutKinds.box_id(&1.merged_into || ""))
      |> Enum.reject(&(is_nil(&1) or &1 in ids))

    %{additions: additions(), box: box ++ WorkoutKindStore.box_kinds_by_ids(Enum.uniq(targets))}
  end

  # Discipline suggestions join the queue under their folded name (the same
  # keys as the workout kinds); noting one twice changes nothing.
  defp sync_profile_suggestions(now) do
    SuggestBoxTag.pending()
    |> Enum.filter(&(Map.get(&1, :list) == "disciplines"))
    |> Enum.each(fn suggestion ->
      WorkoutKindStore.note_profile_suggestion(
        suggestion.name,
        WorkoutKinds.fold(suggestion.name),
        suggestion.id,
        now
      )
    end)
  end

  @doc """
  The Palee team's decision on a name:

    * `%{"decision" => "adopt", "key", "family", "labels" => %{locale => label}}`
    * `%{"decision" => "alias", "target" => kind key}`
    * `%{"decision" => "keep"}`
  """
  def decide(candidate_id, params, actor_user_id, now \\ DateTime.utc_now()) do
    with %{status: "pending"} = candidate <-
           pending_candidate(WorkoutKindStore.get_candidate(candidate_id)),
         {:ok, status, decision, addition} <- decision(params),
         {:ok, decided} <-
           WorkoutKindStore.record_decision(
             candidate.id,
             status,
             decision,
             addition,
             actor_user_id,
             now
           ) do
      apply_decision(decided, decision)
      {:ok, decided}
    end
  end

  # A decided name is not decided again.
  defp pending_candidate(%{status: "pending"} = candidate), do: candidate
  defp pending_candidate(_candidate), do: {:error, :not_found}

  defp decision(params) do
    case field(params, :decision) do
      "adopt" -> adopt_decision(params)
      "alias" -> alias_decision(field(params, :target))
      "keep" -> {:ok, "kept", %{"decision" => "keep"}, nil}
      _other -> {:error, :invalid_workout_kind_decision}
    end
  end

  defp adopt_decision(params) do
    key = field(params, :key)
    labels = labels(field(params, :labels))

    with {:ok, family} <- family(field(params, :family)),
         true <-
           (is_binary(key) and Regex.match?(WorkoutKinds.key_format(), key)) ||
             {:error, :invalid_workout_kind_key},
         false <- WorkoutType.valid?(key) && {:error, :workout_kind_key_taken},
         true <-
           Enum.all?(@locales, &Map.has_key?(labels, &1)) ||
             {:error, :workout_kind_labels_required} do
      {:ok, "adopted", %{"decision" => "adopt", "target" => key, "family" => family},
       %{key: key, family: family, labels: labels}}
    end
  end

  defp alias_decision(target) when is_binary(target) do
    if WorkoutType.valid?(target) or Enum.any?(additions(), &(&1.key == target)),
      do: {:ok, "aliased", %{"decision" => "alias", "target" => target}, nil},
      else: {:error, :invalid_workout_kind}
  end

  defp alias_decision(_target), do: {:error, :invalid_workout_kind}

  defp labels(labels) when is_map(labels) do
    for {locale, label} <- labels,
        locale = to_string(locale),
        locale in @locales,
        {:ok, label} <- [WorkoutKinds.label(label)],
        into: %{},
        do: {locale, label}
  end

  defp labels(_labels), do: %{}

  # The boxes' types move to the decided kind, each box in its own job, and
  # the matching discipline suggestions are resolved.
  defp apply_decision(candidate, %{"decision" => decision} = details) do
    target = details["target"]

    if decision in ["adopt", "alias"] do
      Enum.each(candidate.organization_ids, fn organization_id ->
        %{
          organization_id: organization_id,
          folded: candidate.folded,
          target: target,
          decision: decision
        }
        |> ApplyWorkoutKindDecisionJob.new()
        |> Oban.insert()
      end)
    end

    status = if decision == "keep", do: "declined", else: "added"
    Enum.each(candidate.profile_suggestion_ids, &SuggestBoxTag.resolve(&1, status))
  end

  @doc """
  One box's part of a decision: its types with the folded name merge into
  `target`, and its owners hear about it. Run by `ApplyWorkoutKindDecisionJob`
  in the box's tenant context.
  """
  def apply_to_box(context, folded, target, decision) do
    context
    |> WorkoutKindStore.box_kinds_with_folded(folded)
    |> Enum.each(fn kind ->
      with {:ok, %{workouts: workouts}} <-
             WorkoutKindStore.merge_box_kind(context, kind.id, target) do
        notify_owners(context.organization_id, kind, target, decision, workouts)
      end
    end)
  end

  defp notify_owners(organization_id, kind, target, decision, workouts) do
    box =
      organization_id |> List.wrap() |> Palee.Application.PublicBox.boxes() |> List.first() || %{}

    organization_id
    |> Organizations.list_owner_user_ids()
    |> Enum.each(fn user_id ->
      Notifications.process_event("workout_kind_adopted", %{
        organization_id: organization_id,
        user_id: user_id,
        kind_id: kind.id,
        label: kind.label,
        target: target,
        decision: decision,
        workouts: workouts,
        box_name: Map.get(box, :name),
        box_slug: Map.get(box, :slug)
      })
    end)
  end

  @doc """
  The daily email to the Palee team: the names that arrived since the last
  one. Nothing is sent on a day without news.
  """
  def send_digest(now \\ DateTime.utc_now()) do
    sync_profile_suggestions(now)

    case WorkoutKindStore.undigested_candidates() do
      [] ->
        :none

      candidates ->
        case Application.get_env(:palee, :workout_kinds_team, [])[:team_email] do
          email when is_binary(email) and email != "" ->
            _delivery =
              Email.enqueue(
                :workout_kinds_digest,
                email,
                %{
                  names: Enum.map(candidates, &digest_line/1),
                  url: PublicURL.base_url() <> "/platform/workout-kinds"
                },
                locale:
                  Application.get_env(:palee, :workout_kinds_team, [])[:team_locale] || "el",
                idempotency_key: "workout_kinds_digest:#{Date.to_iso8601(DateTime.to_date(now))}",
                now: now
              )

            WorkoutKindStore.mark_digested(Enum.map(candidates, & &1.id), now)
            {:sent, length(candidates)}

          _none ->
            :no_address
        end
    end
  end

  defp digest_line(candidate) do
    %{
      label: candidate.label,
      boxes: length(candidate.organization_ids),
      suggestions: length(candidate.profile_suggestion_ids)
    }
  end

  defp family(value) do
    if WorkoutKinds.family?(value), do: {:ok, value}, else: {:error, :invalid_workout_kind_family}
  end

  defp field(params, key) when is_map(params),
    do: Map.get(params, key, Map.get(params, Atom.to_string(key)))

  defp field(_params, _key), do: nil
end

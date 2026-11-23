defmodule Palee.Anatomy.Domain.GoalSuggestion do
  @moduledoc """
  Deterministic WOD-goal suggestion from a workout's exercises (ADR-163, D3).

  Input is a list of `%{exercise_ref, weight}` (weight = how much of the
  workout the exercise is, e.g. its set count; defaults to 1). Each exercise
  contributes its curated targets (`ExerciseTargets`):

    * a muscle's goal role is the strongest role any exercise gives it; every
      muscle any exercise names is kept, stabilizers included (ADR-731: coaches
      expect the whole picture, and coverage already gives stabilizers no
      volume);
    * a head is dropped when its group is already a goal with an equal or
      stronger role (the group already says it);
    * qualities are ranked by the weight of the exercises that develop them
      and the strongest ones are kept.

  The coach edits the result; nothing here is ever shown without that chance.
  """

  alias Palee.Anatomy.Domain.{ExerciseTargets, FitnessQualities, MuscleTaxonomy}

  @max_qualities 5
  @quality_share 0.2

  @doc """
  ADR-570: folds a new suggestion into goals the coach already edited, only
  upwards: a suggested muscle the goals lack is added, one they hold with a
  weaker role is promoted (stabilizer → secondary/primary, secondary →
  primary); nothing is removed or demoted. A suggested head is left out when
  the goals already hold its group with an equal or stronger role.
  Qualities are joined. Roles may be atoms or strings; strings come back.
  """
  def merge_up(%{muscles: current, qualities: current_qualities}, %{
        muscles: suggested,
        qualities: suggested_qualities
      }) do
    rank = fn role -> ExerciseTargets.role_rank(role_atom(role)) end
    held = Map.new(current, &{&1.id, to_string(&1.role)})

    merged =
      Enum.reduce(suggested, held, fn %{id: id, role: role}, acc ->
        role = to_string(role)
        group = MuscleTaxonomy.group_of(id)

        cond do
          group != id and Map.has_key?(acc, group) and rank.(acc[group]) >= rank.(role) -> acc
          not Map.has_key?(acc, id) -> Map.put(acc, id, role)
          rank.(role) > rank.(acc[id]) -> Map.put(acc, id, role)
          true -> acc
        end
      end)

    %{
      muscles:
        merged
        |> Enum.map(fn {id, role} -> %{id: id, role: role} end)
        |> Enum.sort_by(fn %{id: id, role: role} -> {-rank.(role), order(id)} end),
      qualities: FitnessQualities.normalize(current_qualities ++ suggested_qualities)
    }
  end

  @doc """
  ADR-671: what a suggestion gained since `basis` (an earlier suggestion of
  the same workout): the muscles it names with a stronger role than the
  basis gave them (or that the basis lacked) and the qualities the basis
  lacked. Folded into edited goals with `merge_up/2`, this adds only what new
  exercises bring, so a muscle the coach removed stays removed. A nil basis
  gains the whole suggestion.
  """
  def gained(nil, suggested), do: Map.take(suggested, [:muscles, :qualities])

  def gained(%{muscles: basis_muscles, qualities: basis_qualities}, %{
        muscles: suggested,
        qualities: suggested_qualities
      }) do
    rank = fn role -> ExerciseTargets.role_rank(role_atom(role)) end
    held = Map.new(basis_muscles, &{&1.id, rank.(&1.role)})

    %{
      muscles: Enum.filter(suggested, &(rank.(&1.role) > Map.get(held, &1.id, 0))),
      qualities: suggested_qualities -- basis_qualities
    }
  end

  defp role_atom(role) when is_atom(role), do: role
  defp role_atom("primary"), do: :primary
  defp role_atom("secondary"), do: :secondary
  defp role_atom("stabilizer"), do: :stabilizer

  def suggest(exercises) when is_list(exercises) do
    resolved =
      exercises
      |> Enum.map(fn exercise ->
        {ExerciseTargets.fetch(field(exercise, :exercise_ref)), weight(exercise)}
      end)
      |> Enum.reject(fn {targets, _weight} -> is_nil(targets) end)

    total = resolved |> Enum.map(&elem(&1, 1)) |> Enum.sum()

    %{
      muscles: muscles(resolved, total),
      qualities: qualities(resolved, total),
      matched_exercises: length(resolved),
      unmatched_exercises: length(exercises) - length(resolved)
    }
  end

  defp muscles(_resolved, total) when total <= 0, do: []

  defp muscles(resolved, _total) do
    goals =
      Enum.reduce(resolved, %{}, fn {%{muscles: muscles}, _weight}, acc ->
        Enum.reduce(muscles, acc, fn %{id: id, role: role}, acc ->
          Map.update(acc, id, role, &stronger(&1, role))
        end)
      end)

    goals
    |> Enum.reject(fn {id, role} -> covered_by_group?(id, role, goals) end)
    |> Enum.map(fn {id, role} -> %{id: id, role: role} end)
    |> Enum.sort_by(fn %{id: id, role: role} -> {-ExerciseTargets.role_rank(role), order(id)} end)
  end

  defp covered_by_group?(id, role, goals) do
    case MuscleTaxonomy.fetch(id) do
      %{kind: :head, group_id: group_id} ->
        case Map.fetch(goals, group_id) do
          {:ok, group_role} ->
            ExerciseTargets.role_rank(group_role) >= ExerciseTargets.role_rank(role)

          :error ->
            false
        end

      _other ->
        false
    end
  end

  defp qualities(_resolved, total) when total <= 0, do: []

  defp qualities(resolved, total) do
    resolved
    |> Enum.flat_map(fn {%{qualities: qualities}, weight} ->
      Enum.map(qualities, &{&1, weight})
    end)
    |> Enum.reduce(%{}, fn {id, weight}, acc -> Map.update(acc, id, weight, &(&1 + weight)) end)
    |> Enum.filter(fn {_id, weight} -> weight / total >= @quality_share end)
    |> Enum.sort_by(fn {id, weight} ->
      {-weight, Enum.find_index(FitnessQualities.all(), &(&1 == id))}
    end)
    |> Enum.take(@max_qualities)
    |> Enum.map(&elem(&1, 0))
  end

  defp stronger(a, b),
    do: if(ExerciseTargets.role_rank(a) >= ExerciseTargets.role_rank(b), do: a, else: b)

  defp order(id), do: MuscleTaxonomy.order(id)

  defp weight(exercise) do
    case field(exercise, :weight) do
      w when is_number(w) and w > 0 -> w
      _other -> 1
    end
  end

  defp field(map, key) when is_map(map), do: Map.get(map, key) || Map.get(map, to_string(key))
  defp field(_map, _key), do: nil
end

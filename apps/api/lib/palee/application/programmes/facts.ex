defmodule Palee.Application.Programmes.Facts do
  @moduledoc """
  ADR-542: «κύριος εξοπλισμός» and «περίπου ανά προπόνηση» of a programme,
  derived from its WODs (`ProgrammeFacts`) with what Workouts knows of each
  WOD: the equipment its exercises need (the canonical catalogue's
  `ExerciseEquipment`) and its `estimated_duration_seconds`.

  A published version keeps the facts of its frozen WODs (`facts`), so
  public pages read them without opening a WOD; a version published before
  ADR-542 derives them on read. The staff editor derives them from the
  draft.
  """

  alias Palee.{Programmes, Workouts}

  @doc "The facts of `days` (draft or version rows), read from the WODs."
  def derive(context, days) do
    workouts =
      days
      |> Programmes.workout_ids()
      |> Map.new(fn id -> {id, workout_facts(Workouts.get_workout(context, id))} end)

    Programmes.derive_facts(days, workouts, Workouts.equipment_keys())
  end

  defp workout_facts(%{} = workout) do
    %{
      equipment: Workouts.workout_equipment(workout).equipment,
      duration_seconds: workout[:estimated_duration_seconds],
      type: workout_type(workout[:type])
    }
  end

  defp workout_facts(_missing), do: %{equipment: [], duration_seconds: nil, type: nil}

  # The ADR-275 kind, only when it is one of the list (never "" or a stray value).
  defp workout_type(type) do
    type = type && to_string(type)
    if type in Workouts.workout_type_keys(), do: type
  end

  @doc """
  A version's stored facts, or derived from its WODs (versions published
  before ADR-542, or before the day outline was stored with them).
  """
  def of_version(_context, nil), do: nil
  def of_version(_context, %{facts: %{"days" => _days} = facts}), do: facts
  def of_version(context, version), do: derive(context, version.days)

  @doc """
  What a page shows: `main_equipment` (the author's added keys, then the
  derived ones the author kept) and `minutes_per_session`.
  """
  def shown(programme, facts) do
    vocabulary = Workouts.equipment_keys()
    added = Enum.filter(programme.equipment || [], &(&1 in vocabulary))
    removed = Map.get(programme, :equipment_removed) || []
    facts = facts || %{}

    %{
      main_equipment:
        Programmes.effective_equipment(Map.get(facts, "equipment", []), added, removed),
      minutes_per_session: Map.get(facts, "minutes_per_session")
    }
  end
end

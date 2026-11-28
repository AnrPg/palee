defmodule Palee.Application.ClassVariants do
  @moduledoc """
  ADR-785: what happens to a member's «Παραλλαγή» of one class after it is
  made (it is made by `ProgramUserWorkout`, mode `class_variant`).

    * `keep/3` – staff, on the roster's «Το WOD άλλαξε μετά την
      παραλλαγή»: «Κράτησέ τη» takes the class WOD as it reads now as the
      variant's new starting point, so the notice goes away.
    * `set_active/4` – the member: `false` goes back to a WOD of the class
      (the variant stays, in case they come back), `true` does the variant
      again.
    * `handle_event(:class_cancelled, …)` – a cancelled or deleted class
      takes its variants with it (γ). A cancelled booking does not.
  """

  alias Palee.Application.BroadcastUserSync
  alias Palee.{Scheduling, Workouts}

  @doc "«Κράτησέ τη»: the variant now counts as made from the class WOD as it reads today."
  def keep(%{organization_id: _} = context, slot_id, assignment_id) do
    with %{} = slot <- Scheduling.get_slot(context, slot_id) || {:error, :not_found},
         %{} = variant <- find(context, slot.id, nil, assignment_id),
         {:ok, _updated} <-
           Workouts.update_class_variant(context, variant.assignment_id, %{
             variant_source_hash: current_hash(context, Map.get(variant, :variant_of_workout_id))
           }) do
      sync(variant)
      :ok
    else
      nil -> {:error, :class_variant_not_found}
      error -> error
    end
  end

  def keep(_context, _slot_id, _assignment_id), do: {:error, :organization_context_required}

  @doc "The member does their variant (`true`) or a WOD of the class (`false`)."
  def set_active(%{organization_id: _} = context, %{id: member_id}, slot_id, active?)
      when is_boolean(active?) do
    with %{} = variant <- find(context, slot_id, member_id, nil),
         {:ok, _updated} <-
           Workouts.update_class_variant(context, variant.assignment_id, %{
             variant_set_aside_at: if(active?, do: nil, else: DateTime.utc_now())
           }) do
      sync(variant)
      :ok
    else
      nil -> {:error, :class_variant_not_found}
      error -> error
    end
  end

  def set_active(%{organization_id: _}, _actor, _slot_id, _active), do: {:error, :invalid_params}

  def set_active(_context, _actor, _slot_id, _active),
    do: {:error, :organization_context_required}

  @doc false
  def handle_event(:class_cancelled, %{
        organization_id: organization_id,
        scheduled_class_id: slot_id
      })
      when is_binary(organization_id) and is_binary(slot_id) do
    {:ok, _count} =
      Workouts.delete_class_variants(%{organization_id: organization_id}, slot_id, nil)

    :ok
  end

  def handle_event(_event, _payload), do: :ok

  defp find(context, slot_id, member_id, assignment_id) do
    context
    |> Workouts.list_class_variants([slot_id], member_id)
    |> Enum.find(&(is_nil(assignment_id) or &1.assignment_id == assignment_id))
  end

  defp current_hash(_context, nil), do: nil

  defp current_hash(context, workout_id) do
    case Workouts.get_workout_for_admin(context, workout_id) do
      %{} = workout -> workout |> Workouts.build_snapshot() |> Map.get(:content_hash)
      _missing -> nil
    end
  end

  defp sync(variant) do
    BroadcastUserSync.for_users([variant.assignee_id], ["assigned_workouts"],
      reason: "class_variant_changed",
      payload: %{assignment_id: variant.assignment_id}
    )
  end
end

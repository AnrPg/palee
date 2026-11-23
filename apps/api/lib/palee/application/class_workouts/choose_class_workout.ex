defmodule Palee.Application.ClassWorkouts.ChooseClassWorkout do
  @moduledoc """
  ADR-746: which of a class's WODs a person does.

    * `:member` — the person on their own booking («Ποιο WOD;», the live
      switch, «Ακολούθησε» = nil).
    * `:staff` — a coach for anyone booked in the class, also when the
      person already chose (they chose wrong or changed their mind). The
      person sees «Ο coach σού έβαλε …» and can change it again.

  nil means «Θα αποφασίσω στο box»: the person follows the coach's «Τώρα».
  Seats never move: the choice is not a booking.
  """

  alias Palee.Application.ScheduleRealtime
  alias Palee.{Organizations, Scheduling}
  alias Palee.Scheduling.Domain.ClassWorkouts

  @active [:pending, :approved, "pending", "approved"]

  def call(context, actor, slot_id, workout_id, opts \\ [])

  def call(%{organization_id: _} = context, %{id: actor_id}, slot_id, workout_id, opts) do
    workout_id = blank_to_nil(workout_id)

    with %{} = slot <- Scheduling.get_slot(context, slot_id) || {:error, :not_found},
         {:ok, booking} <- booking(context, slot, actor_id, opts),
         :ok <- valid_choice(slot, workout_id),
         {:ok, updated} <-
           Scheduling.choose_booking_workout(
             context,
             booking.id,
             workout_id,
             actor_id,
             DateTime.utc_now()
           ) do
      ScheduleRealtime.broadcast("class_workout_chosen", %{
        organization_id: slot.organization_id,
        slot_id: slot.id
      })

      {:ok, updated}
    end
  end

  def call(_context, _actor, _slot_id, _workout_id, _opts),
    do: {:error, :organization_context_required}

  defp booking(context, slot, actor_id, opts) do
    case Keyword.get(opts, :booking_id) do
      nil ->
        slot.bookings
        |> Enum.find(
          &(&1.user_id == actor_id and is_nil(Map.get(&1, :guest_name)) and &1.status in @active)
        )
        |> found()

      booking_id ->
        with :ok <- Organizations.authorize_location(context, Map.get(slot, :location_id)) do
          slot.bookings
          |> Enum.find(&(&1.id == booking_id and &1.status in @active))
          |> found()
        end
    end
  end

  defp found(nil), do: {:error, :not_found}
  defp found(booking), do: {:ok, booking}

  defp valid_choice(_slot, nil), do: :ok

  defp valid_choice(slot, workout_id),
    do: if(ClassWorkouts.member?(slot, workout_id), do: :ok, else: {:error, :not_a_class_workout})

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value
end

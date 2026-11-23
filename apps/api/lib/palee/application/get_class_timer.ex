defmodule Palee.Application.GetClassTimer do
  @moduledoc """
  Reads a class timer: any active member of the gym may follow it.
  ADR-746: `workout_id` reads the timer of one of the class's WODs; nil
  reads the coach's «Τώρα».
  """

  alias Palee.Application.ClassTimerView

  @viewer_roles [:owner, :admin, :coach, :athlete, :member]

  def call(context, slot_id, workout_id \\ nil)

  def call(%{role: role} = context, slot_id, workout_id) when role in @viewer_roles do
    with {:ok, view} <- ClassTimerView.load(context, slot_id, workout_id) do
      {:ok, ClassTimerView.payload(view, DateTime.utc_now())}
    end
  end

  def call(_context, _slot_id, _workout_id), do: {:error, :forbidden}
end

defmodule Palee.Workouts.Domain.LoggedWorkoutChange do
  @moduledoc """
  ADR-393: who hears that a WOD changed after they performed it. Pure.

  A save of a WOD (one publish, however many fields it changed) reaches only
  the people whose own run or score points at a snapshot (ADR-357) that no
  longer reads like the WOD now: exactly those whose Journal shows «Το WOD
  άλλαξε από τότε» (ADR-389). Each person hears once per save, about their
  latest run or score of it; the editor never hears about their own edit.
  People whose result predates snapshots have nothing to compare, so they
  are left alone, as the Journal does.
  """

  @type performed :: %{
          required(:user_id) => String.t(),
          required(:holder) => :execution | :training_log,
          required(:holder_id) => String.t(),
          required(:content_hash) => String.t(),
          optional(:at) => DateTime.t() | nil
        }

  @doc """
  One entry per person to tell, their latest run or score whose snapshot
  differs from `current_hash`, without `editor_id`. Ordered by person.
  """
  @spec recipients([performed()], String.t(), String.t() | nil) :: [performed()]
  def recipients(performed, current_hash, editor_id) when is_binary(current_hash) do
    performed
    |> Enum.reject(&(&1.content_hash == current_hash or &1.user_id == editor_id))
    |> Enum.group_by(& &1.user_id)
    |> Enum.map(fn {_user_id, results} -> Enum.max_by(results, &moment/1, &later?/2) end)
    |> Enum.sort_by(& &1.user_id)
  end

  def recipients(_performed, _current_hash, _editor_id), do: []

  @doc """
  The notification's dedupe key: one per person, WOD and content now (a
  second save that changes nothing, or a retried request, adds nothing).
  """
  @spec dedupe_key(String.t(), String.t()) :: String.t()
  def dedupe_key(workout_id, current_hash),
    do: "logged_workout_changed:#{workout_id}:#{current_hash}"

  @doc "Where the notification opens: the Journal, on that run or score."
  @spec journal_url(String.t()) :: String.t()
  def journal_url(holder_id), do: "/journal?entry=#{holder_id}"

  defp moment(%{at: %DateTime{} = at}), do: at
  defp moment(_result), do: nil

  defp later?(nil, _other), do: false
  defp later?(_at, nil), do: true
  defp later?(a, b), do: DateTime.compare(a, b) != :lt
end

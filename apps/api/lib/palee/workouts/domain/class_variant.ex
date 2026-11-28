defmodule Palee.Workouts.Domain.ClassVariant do
  @moduledoc """
  ADR-785: rules for a member's «Παραλλαγή» of one class (an assignment
  linked to the class occurrence, ADR-125). Pure, over facts the caller
  already read.

    * `stands_in_for/3` – the class WOD the variant replaces: the source the
      coach started from when it is one of the class's WODs, else the WOD
      the member does in that class (their pick, or «Τώρα»).
    * `stale/3` – what the coach is told on the roster: `"removed"` when that
      WOD left the class, `"changed"` when its content differs from the
      content the variant was made from (or kept against), else nil.
    * `active?/1` – the member does the variant (they did not go back to a
      class WOD).
  """

  @type stale :: nil | String.t()

  @doc "The class WOD a new variant stands in for."
  @spec stands_in_for(String.t() | nil, [String.t()], String.t() | nil) :: String.t() | nil
  def stands_in_for(source_id, class_workout_ids, member_workout_id) do
    cond do
      is_binary(source_id) and source_id in class_workout_ids -> source_id
      is_binary(member_workout_id) and member_workout_id in class_workout_ids -> member_workout_id
      true -> List.first(class_workout_ids)
    end
  end

  @doc """
  `"removed"`, `"changed"` or nil. `current_hashes` maps a class WOD id to
  its content hash now. A variant made before ADR-785 (no `variant_of`) is
  never reported.
  """
  @spec stale(map(), [String.t()], %{optional(String.t()) => String.t()}) :: stale()
  def stale(variant, class_workout_ids, current_hashes) do
    of = Map.get(variant, :variant_of_workout_id)
    kept = Map.get(variant, :variant_source_hash)

    cond do
      not is_binary(of) ->
        nil

      of not in class_workout_ids ->
        "removed"

      is_binary(kept) and Map.has_key?(current_hashes, of) and current_hashes[of] != kept ->
        "changed"

      true ->
        nil
    end
  end

  @doc "Whether the member does the variant (nil `set_aside_at`)."
  @spec active?(map()) :: boolean()
  def active?(variant), do: is_nil(Map.get(variant, :set_aside_at))
end

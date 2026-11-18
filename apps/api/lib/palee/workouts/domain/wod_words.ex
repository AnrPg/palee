defmodule Palee.Workouts.Domain.WodWords do
  @moduledoc """
  The word tokens of a line of workout text, shared by every reader of free
  text (goal suggestion `FreeTextExercises`, ADR-570 `ExerciseMatcher`).

  A count or multiplier written against the next word ("20xBack Extension",
  "10Burpees", "3×Pull-ups", "5χ Κάμψεις", "21-thrusters") is its own token,
  so the movement after it is still read; the count token holds a digit and
  readers skip it as a number. A word that merely contains digits ("T2B",
  "21-15-9") stays one token.
  """

  # 1. a count glued to the following letters: digits, an optional decimal
  #    part, an optional multiplier sign (Latin x, ×, Greek χ) and an optional
  #    hyphen, when a letter comes next;
  # 2. otherwise a word: letters and digits with inner apostrophes,
  #    ampersands and hyphens.
  @token ~r/\d+(?:[.,]\d+)?[xX×χΧ]?-?(?=\p{L})|[\p{L}\p{N}][\p{L}\p{N}'’&-]*/u

  @doc "The token pattern (`Regex.scan/3` with `return: :index` gives offsets)."
  def pattern, do: @token

  @doc "The tokens of `text`, as written."
  def tokens(text) when is_binary(text), do: @token |> Regex.scan(text) |> List.flatten()
end

defmodule Palee.Workouts.Domain.FreeTextExercises do
  @moduledoc """
  Deterministic, best-effort reading of the exercises in a free-text
  workout body, for WOD-goal suggestion (ADR-163). No assistant is involved:
  each line is scanned for the longest run of words that names a Quick Text
  catalog entry (canonical label or alias, singular or plural), so

      21-15-9
      Thrusters (43/30 kg)
      Pull-ups

  yields thruster and pull-up. A line naming nothing known is reported as
  one unmatched exercise; blank and pure-number lines are skipped. A leading
  `5x5` or `5 x 3` on a line is read as its set count.
  """

  alias Palee.Workouts.Domain.WorkoutDsl.ExerciseCatalog

  @max_lines 80
  @max_window 4

  @doc "Exercises named in `text`: `%{name, exercise_ref, category, weight}`."
  def from_text(text) when is_binary(text) do
    text
    |> String.split(["\r\n", "\n", "\r"])
    |> Enum.take(@max_lines)
    |> Enum.flat_map(&line_exercises/1)
  end

  def from_text(_text), do: []

  @doc """
  ADR-570: exercises of a document's lines (`FreeTextDocument.lines/1`): a
  linked span counts as its exercise, a span the coach rejected (and the
  same words elsewhere in the workout) counts as nothing, and the rest of
  each line is read as `from_text/1` reads it.
  """
  def from_lines(lines) when is_list(lines) do
    rejected =
      for line <- lines,
          link <- line.links,
          is_nil(link.ref),
          into: MapSet.new(),
          do: fold_words(link.text)

    lines
    |> Enum.take(@max_lines)
    |> Enum.flat_map(fn line ->
      weight = sets(line.text)

      linked =
        for %{ref: ref} <- line.links,
            is_binary(ref),
            entry = ExerciseCatalog.fetch(ref),
            entry != nil do
          %{name: entry.label, exercise_ref: entry.id, category: entry.category, weight: weight}
        end

      rest = line.text |> blank_spans(line.links) |> blank_rejected(rejected)

      case line_exercises(rest, weight) do
        [%{exercise_ref: nil}] when line.links != [] -> linked
        found -> linked ++ found
      end
    end)
  end

  @doc """
  Resolves one exercise name leniently: as written, then with a plural last
  word made singular. Returns the catalog entry or `nil`.
  """
  def resolve_name(name) when is_binary(name) do
    words = words(name)
    if words == [], do: nil, else: resolve_words(words)
  end

  def resolve_name(_name), do: nil

  defp line_exercises(line, weight \\ nil) do
    words = words(line)

    if words == [] do
      []
    else
      weight = weight || sets(line)

      case scan(words, []) do
        [] ->
          [%{name: String.trim(line), exercise_ref: nil, category: nil, weight: weight}]

        entries ->
          entries
          |> Enum.reverse()
          |> Enum.map(
            &%{name: &1.label, exercise_ref: &1.id, category: &1.category, weight: weight}
          )
      end
    end
  end

  # Longest match first at each position; a matched run is consumed.
  defp scan([], found), do: found

  defp scan(words, found) do
    max = min(@max_window, length(words))

    match =
      Enum.find_value(max..1//-1, fn size ->
        case resolve_words(Enum.take(words, size)) do
          nil -> nil
          entry -> {entry, size}
        end
      end)

    case match do
      {entry, size} -> scan(Enum.drop(words, size), [entry | found])
      nil -> scan(tl(words), found)
    end
  end

  defp resolve_words(words) do
    candidates = [words, singular(words)] |> Enum.uniq()

    Enum.find_value(candidates, fn candidate ->
      case ExerciseCatalog.resolve(Enum.join(candidate, " ")) do
        {:ok, entry, _kind} -> entry
        {:error, _reason} -> nil
      end
    end)
  end

  defp singular(words) do
    {last, rest} = List.pop_at(words, -1)

    singular =
      cond do
        String.ends_with?(last, "ies") and byte_size(last) > 4 ->
          String.slice(last, 0..-4//1) <> "y"

        String.ends_with?(last, "ss") ->
          last

        String.ends_with?(last, "s") and byte_size(last) > 2 ->
          String.slice(last, 0..-2//1)

        true ->
          last
      end

    rest ++ [singular]
  end

  # Words that can name a movement: no numbers, loads or units. Text in
  # brackets (loads, scaling notes) is dropped.
  @noise ~w(x kg kgs lb lbs m km cal cals rep reps round rounds rft amrap emom for time min mins sec secs of then rest)
  defp words(text) do
    text
    |> String.downcase()
    |> String.replace(~r/\([^)]*\)|\[[^\]]*\]/u, " ")
    |> String.replace(~r/[^\p{L}\p{N}&'\s-]+/u, " ")
    |> String.replace(~r/[\s_-]+/u, " ")
    |> String.split(" ", trim: true)
    |> Enum.reject(&(Regex.match?(~r/\d/u, &1) or &1 in @noise))
  end

  defp blank_spans(text, links) do
    Enum.reduce(links, text, fn %{from: from, to: to}, acc ->
      String.slice(acc, 0, from) <>
        String.duplicate(" ", to - from) <> String.slice(acc, to..-1//1)
    end)
  end

  defp blank_rejected(text, rejected) do
    if MapSet.size(rejected) == 0 do
      text
    else
      folded = fold_words(text)

      Enum.reduce(rejected, text, fn words, acc ->
        if words != "" and String.contains?(folded, words),
          do: replace_folded(acc, words),
          else: acc
      end)
    end
  end

  # Replaces every run of `acc` whose folded form is `words` by spaces.
  defp replace_folded(text, words) do
    pattern =
      words
      |> String.split(" ", trim: true)
      |> Enum.map_join("[\\s_-]+", &Regex.escape/1)

    folded = fold_chars(text)

    case Regex.compile("(?<![\\p{L}])" <> pattern <> "(?![\\p{L}])", "u") do
      {:ok, regex} ->
        regex
        |> Regex.scan(folded, return: :index)
        |> Enum.reduce(text, fn [{start, len}], acc ->
          from = folded |> binary_part(0, start) |> String.length()
          to = folded |> binary_part(0, start + len) |> String.length()

          String.slice(acc, 0, from) <>
            String.duplicate(" ", to - from) <> String.slice(acc, to..-1//1)
        end)

      _error ->
        text
    end
  end

  # Lower case, accents dropped, one character per character (offsets kept).
  defp fold_chars(text) do
    text
    |> String.graphemes()
    |> Enum.map_join(fn g ->
      case g |> String.normalize(:nfd) |> String.replace(~r/\p{Mn}/u, "") |> String.downcase() do
        "" -> g
        <<_::utf8>> = one -> if one == "ς", do: "σ", else: one
        _longer -> String.first(String.downcase(g))
      end
    end)
  end

  defp fold_words(text),
    do: text |> fold_chars() |> String.replace(~r/[\s_-]+/u, " ") |> String.trim()

  defp sets(line) do
    case Regex.run(~r/^\s*(\d{1,2})\s*[x×]\s*\d+/u, line) do
      [_match, count] -> max(String.to_integer(count), 1)
      _none -> 1
    end
  end
end

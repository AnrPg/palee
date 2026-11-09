defmodule Palee.Workouts.Domain.ExerciseMatcher do
  @moduledoc """
  ADR-570: finds catalog exercises in the lines of a free-text workout, with
  where each one was written, so the coach can confirm them before
  publishing. Optimistic: as many as possible are found, and every one found
  is a question, never a silent decision.

  Each line is read as runs of words (no numbers, units, loads or bracketed
  notes). At each word the longest run (up to four words) that names an
  exercise wins and is consumed. A run names an exercise when, against the
  exercise's label, its Quick Text aliases or its search aliases (Greek
  names, abbreviations):

    * **exact**: equal once folded (case, accents, Greek final sigma), spaces
      and hyphens removed and a plural `s` ignored ("Pull ups" = "Pull-up");
    * **fuzzy**: close under a typo model: Greek letters transliterated,
      common spelling variants folded (`ph`→`f`, `ck`→`k`, `y`→`i`, doubled
      letters), then an optimal-string-alignment distance (insertions,
      deletions, substitutions and swapped neighbours) within a budget that
      grows with the name's length (1 edit from 4 letters, 2 from 6, 3 from
      10), after a bigram pre-filter. "thrsuters", "pulups", "dubel unders"
      and "θραστερ" are found; short words never match fuzzily.

  Pure: the catalog comes in as `names/1`.
  """

  alias Palee.Transliteration

  @max_window 4
  @noise ~w(x kg kgs lb lbs m km cal cals rep reps round rounds rft amrap emom for time min mins sec secs of then rest and με και the a every each on off)

  @type name_entry :: %{
          exercise_ref: String.t(),
          name: String.t(),
          key: String.t(),
          bigrams: MapSet.t()
        }

  @doc """
  The catalog's matchable names: `entries` are `%{id, label, aliases}` and
  `search_aliases` a function from id to that exercise's search aliases.
  """
  def names(entries, search_aliases) do
    entries
    |> Enum.flat_map(fn entry ->
      [entry.label | entry.aliases ++ search_aliases.(entry.id)]
      |> Enum.uniq()
      |> Enum.map(&name_entry(entry.id, entry.label, &1))
    end)
    |> Enum.reject(&(&1.key == ""))
  end

  defp name_entry(id, label, name) do
    key = key(name)
    %{exercise_ref: id, label: label, name: name, key: key, bag: bag(name), bigrams: bigrams(key)}
  end

  @doc """
  Matches in one line: `%{from, to, typed, exercise_ref, label, kind}` with
  `from`/`to` codepoint offsets into `line` and `kind` `:exact | :fuzzy`.
  `skip?` gets `{from, to}` and drops a run (a span already linked).
  """
  def match_line(line, names, skip? \\ fn _span -> false end) when is_binary(line) do
    line |> runs() |> Enum.flat_map(&scan(&1, names, skip?, line, []))
  end

  @doc "Resolves one written name (a linked span's text): `{ref, kind}` or nil."
  def resolve(text, names) when is_binary(text) do
    case best(text, names) do
      nil -> nil
      %{entry: entry, kind: kind} -> {entry.exercise_ref, kind}
    end
  end

  @doc "The folded form used to remember a decision (`exercise_match_memories.folded`)."
  def folded(text) when is_binary(text),
    do: text |> fold() |> String.replace(~r/\s+/u, " ") |> String.trim()

  # -- Scanning ---------------------------------------------------------------

  # Runs of consecutive word tokens `[{word, from, to}]`; noise, numbers and
  # bracketed text break a run.
  defp runs(line) do
    brackets =
      ~r/\([^)]*\)|\[[^\]]*\]/u
      |> Regex.scan(line, return: :index)
      |> Enum.map(fn [{start, len}] -> {cp(line, start), cp(line, start + len)} end)

    ~r/[\p{L}\p{N}][\p{L}\p{N}'’&-]*/u
    |> Regex.scan(line, return: :index)
    |> Enum.map(fn [{start, len}] ->
      from = cp(line, start)
      {binary_part(line, start, len), from, from + String.length(binary_part(line, start, len))}
    end)
    |> Enum.chunk_while(
      [],
      fn {word, from, to} = token, acc ->
        cond do
          noise?(word) or Enum.any?(brackets, fn {a, b} -> from >= a and to <= b end) ->
            if acc == [], do: {:cont, []}, else: {:cont, Enum.reverse(acc), []}

          true ->
            {:cont, [token | acc]}
        end
      end,
      fn
        [] -> {:cont, []}
        acc -> {:cont, Enum.reverse(acc), []}
      end
    )
  end

  defp noise?(word) do
    lower = String.downcase(word)
    Regex.match?(~r/\d/u, word) or lower in @noise or Regex.match?(~r/^\d+[x×]?$/u, lower)
  end

  defp scan([], _names, _skip?, _line, found), do: Enum.reverse(found)

  defp scan(tokens, names, skip?, line, found) do
    max = min(@max_window, length(tokens))

    hit =
      Enum.find_value(max..1//-1, fn size ->
        window = Enum.take(tokens, size)
        {_w, from, _t} = hd(window)
        {_w, _f, to} = List.last(window)

        with false <- skip?.({from, to}),
             typed = slice(line, from, to),
             %{} = match <- best(typed, names) do
          {size,
           %{
             from: from,
             to: to,
             typed: typed,
             exercise_ref: match.entry.exercise_ref,
             label: match.entry.label,
             kind: match.kind
           }}
        else
          _none -> nil
        end
      end)

    case hit do
      {size, match} -> scan(Enum.drop(tokens, size), names, skip?, line, [match | found])
      nil -> scan(tl(tokens), names, skip?, line, found)
    end
  end

  # -- Scoring ----------------------------------------------------------------

  defp best(text, names) do
    key = key(text)

    if byte_size(key) < 2,
      do: nil,
      else: exact(key, names) || reordered(bag(text), names) || fuzzy(key, names)
  end

  defp exact(key, names) do
    case Enum.find(names, &(&1.key == key)) do
      nil -> nil
      entry -> %{entry: entry, kind: :exact}
    end
  end

  # The same words in another order ("Σχοινάκι διπλό" = «Διπλό σχοινάκι»).
  defp reordered(nil, _names), do: nil

  defp reordered(bag, names) do
    case Enum.find(names, &(&1.bag == bag)) do
      nil -> nil
      entry -> %{entry: entry, kind: :fuzzy}
    end
  end

  # Two or more words, as a sorted list of word keys; nil for one word.
  defp bag(text) do
    case text
         |> String.split(~r/[\s_-]+/u, trim: true)
         |> Enum.map(&key/1)
         |> Enum.reject(&(&1 == "")) do
      [_one] -> nil
      [] -> nil
      words -> Enum.sort(words)
    end
  end

  defp fuzzy(key, names) do
    length = String.length(key)
    budget = budget(length)

    if budget == 0 do
      nil
    else
      grams = bigrams(key)

      names
      |> Enum.filter(fn entry ->
        abs(String.length(entry.key) - length) <= budget and dice(grams, entry.bigrams) >= 0.34
      end)
      |> Enum.map(fn entry -> {distance(key, entry.key), entry} end)
      |> Enum.filter(fn {d, entry} -> d <= min(budget, budget(String.length(entry.key))) end)
      |> Enum.min_by(fn {d, entry} -> {d, -String.length(entry.key)} end, fn -> nil end)
      |> case do
        nil -> nil
        {_d, entry} -> %{entry: entry, kind: :fuzzy}
      end
    end
  end

  defp budget(length) when length < 4, do: 0
  defp budget(length) when length < 6, do: 1
  defp budget(length) when length < 10, do: 2
  defp budget(_length), do: 3

  # -- Keys -------------------------------------------------------------------

  defp fold(text) do
    text
    |> String.normalize(:nfd)
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.downcase()
    |> String.replace("ς", "σ")
  end

  # Folded, transliterated, spelling variants evened out, letters only, a
  # trailing plural `s` dropped.
  defp key(text) do
    text
    |> fold()
    |> Transliteration.latin()
    |> String.replace(~r/[^a-z0-9]/u, "")
    |> String.replace("ph", "f")
    |> String.replace("ck", "k")
    |> String.replace("y", "i")
    |> String.replace(~r/(.)\1+/u, "\\1")
    |> String.replace(~r/(?<=.{3})e?s$/u, "")
  end

  defp bigrams(key) do
    key
    |> String.graphemes()
    |> Enum.chunk_every(2, 1, :discard)
    |> MapSet.new()
  end

  defp dice(a, b) do
    total = MapSet.size(a) + MapSet.size(b)
    if total == 0, do: 0.0, else: 2 * MapSet.size(MapSet.intersection(a, b)) / total
  end

  # Optimal string alignment distance (Damerau-Levenshtein, no repeated edits
  # of one substring).
  defp distance(a, b) do
    a = String.graphemes(a) |> List.to_tuple()
    b = String.graphemes(b) |> List.to_tuple()
    n = tuple_size(a)
    m = tuple_size(b)

    {_prev2, prev, _} =
      Enum.reduce(1..n//1, {nil, Enum.to_list(0..m) |> List.to_tuple(), nil}, fn i,
                                                                                 {prev2, prev, _} ->
        row =
          Enum.reduce(1..m//1, [i], fn j, acc ->
            left = hd(acc)
            cost = if elem(a, i - 1) == elem(b, j - 1), do: 0, else: 1
            value = Enum.min([elem(prev, j) + 1, left + 1, elem(prev, j - 1) + cost])

            value =
              if i > 1 and j > 1 and prev2 != nil and elem(a, i - 1) == elem(b, j - 2) and
                   elem(a, i - 2) == elem(b, j - 1),
                 do: min(value, elem(prev2, j - 2) + 1),
                 else: value

            [value | acc]
          end)
          |> Enum.reverse()
          |> List.to_tuple()

        {prev, row, nil}
      end)

    elem(prev, m)
  end

  # -- Offsets ----------------------------------------------------------------

  defp cp(line, byte_offset), do: line |> binary_part(0, byte_offset) |> String.length()

  defp slice(line, from, to), do: String.slice(line, from, to - from)
end

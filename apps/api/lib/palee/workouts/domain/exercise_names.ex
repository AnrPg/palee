defmodule Palee.Workouts.Domain.ExerciseNames do
  @moduledoc """
  ADR-461: exercise names are free text with suggestions. This module is the
  pure half: how a name is folded for matching, the Palee catalog as
  suggestion documents (labels, aliases, abbreviations and Greek forms), the
  Greek ↔ English word synonyms, and the typo-tolerant matcher the Postgres
  fallback ranks with (the same rules as the web's `fuzzy`: every query word
  must match a word of the name as a prefix, inside a word, or with one typo,
  two from seven letters).

  Groups come back in a fixed order, «Έχεις γράψει» (mine), «Του box σου»
  (box), «Palee» (palee), and a name appears once, in the first group that
  has it.
  """

  alias Palee.Workouts.Domain.WorkoutDsl.ExerciseCatalog

  @max_name_length 120
  @sources [:mine, :box, :palee]

  # Word synonyms (folded): what a Greek word, or its Latin spelling, means
  # in the catalog's English names. Meilisearch gets the same pairs.
  @word_synonyms %{
    "σκουατ" => "squat",
    "skouat" => "squat",
    "skuat" => "squat",
    "ντεντλιφτ" => "deadlift",
    "θανατου" => "deadlift",
    "πιεσεις" => "press",
    "πιεση" => "press",
    "παγκου" => "bench",
    "παγκος" => "bench",
    "ωμων" => "shoulder",
    "μπροστινο" => "front",
    "πισω" => "back",
    "πλατης" => "back",
    "κλιν" => "clean",
    "τζερκ" => "jerk",
    "σνατς" => "snatch",
    "αρασε" => "snatch",
    "ζετε" => "jerk",
    "θραστερ" => "thruster",
    "μπερπι" => "burpee",
    "μπερπις" => "burpee",
    "ελξεις" => "pull-up",
    "καμψεις" => "push-up",
    "βυθισεις" => "dip",
    "προβολες" => "lunge",
    "λαντζες" => "lunge",
    "κοιλιακοι" => "sit-up",
    "σανιδα" => "plank",
    "πλανκ" => "plank",
    "αιωρησεις" => "swing",
    "σουινγκ" => "swing",
    "κετλμπελ" => "kettlebell",
    "αλτηρα" => "dumbbell",
    "αλτηρες" => "dumbbell",
    "μπαρα" => "barbell",
    "κουτι" => "box",
    "αλματα" => "jump",
    "αλμα" => "jump",
    "σχοινι" => "rope",
    "σχοινακι" => "under",
    "τρεξιμο" => "run",
    "κωπηλατικη" => "row",
    "κωπηλατικο" => "row",
    "ποδηλατο" => "bike",
    "κολυμπι" => "swim",
    "κατακορυφες" => "handstand",
    "κατακορυφος" => "handstand"
  }

  def max_name_length, do: @max_name_length
  def sources, do: @sources

  @doc "Folds a name or a query: NFD marks stripped, lowercase, final sigma, spaces collapsed."
  def fold(value) when is_binary(value) do
    value
    |> String.normalize(:nfd)
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.downcase()
    |> String.replace("ς", "σ")
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
    |> String.normalize(:nfc)
  end

  def fold(_value), do: ""

  @doc "A typed name, trimmed and capped; `nil` for an empty or non-text one."
  def clean_name(name) when is_binary(name) do
    case name |> String.replace(~r/\s+/u, " ") |> String.trim() do
      "" -> nil
      trimmed -> String.slice(trimmed, 0, @max_name_length)
    end
  end

  def clean_name(_name), do: nil

  @doc """
  The names worth remembering from a list of `%{name, catalog_slug}`-like
  maps (string or atom keys): cleaned, deduplicated by folded form (the last
  spelling wins), each with its catalog slug: the given one when it is in
  the catalog (`docs`, from `catalog_documents/1`), else the entry whose
  label or alias the name is.
  """
  def entries(rows, docs \\ catalog_documents())

  def entries(rows, docs) when is_list(rows) do
    known = MapSet.new(docs, & &1.catalog_slug)

    rows
    |> Enum.flat_map(fn row ->
      case clean_name(value(row, :name)) do
        nil ->
          []

        name ->
          [%{name: name, folded: fold(name), catalog_slug: slug_for(row, name, known, docs)}]
      end
    end)
    |> Enum.reverse()
    |> Enum.uniq_by(& &1.folded)
    |> Enum.reverse()
  end

  def entries(_rows, _docs), do: []

  defp slug_for(row, name, known, docs) do
    given = value(row, :catalog_slug) || value(row, :exercise_ref)

    if is_binary(given) and MapSet.member?(known, given),
      do: given,
      else: resolve_slug(name, docs)
  end

  @doc """
  The exercise rows of a workout with its sections and exercises loaded
  (`%{name, catalog_slug}`); headers and anything not loaded are left out.
  """
  def workout_rows(%{sections: sections}) when is_list(sections) do
    for %{exercises: exercises} <- sections,
        is_list(exercises),
        %{name: name} = exercise <- exercises,
        Map.get(exercise, :item_type, :exercise) in [:exercise, "exercise"],
        is_binary(name),
        do: %{name: name, catalog_slug: Map.get(exercise, :exercise_ref)}
  end

  def workout_rows(_workout), do: []

  @doc "The catalog slug of a name typed exactly as a label or alias (folded), or `nil`."
  def resolve_slug(name, docs \\ catalog_documents())

  def resolve_slug(name, docs) when is_binary(name) do
    key = same_key(name)

    Enum.find_value(docs, fn doc ->
      if same_key(doc.name) == key or Enum.any?(doc.aliases, &(same_key(&1) == key)),
        do: doc.catalog_slug
    end)
  end

  def resolve_slug(_name, _docs), do: nil

  defp same_key(name), do: name |> fold() |> String.replace(~r/[\s_-]+/u, " ")

  @doc """
  The Palee catalog as suggestion documents (ADR-560 reference tables): every
  exercise, built-in or approved by the Palee team, with its Quick Text
  aliases and its search-only aliases.
  """
  def catalog_documents do
    Enum.map(ExerciseCatalog.entries(), fn entry ->
      %{
        catalog_slug: entry.id,
        name: entry.label,
        aliases: entry.aliases ++ ExerciseCatalog.search_aliases(entry.id),
        category: entry.category
      }
    end)
  end

  @doc "Greek ↔ English word synonyms, folded (`%{word => english}`)."
  def word_synonyms, do: @word_synonyms

  @doc "The query and, when it holds a synonym word, its English rewrite."
  def query_variants(query) do
    folded = fold(query)

    rewritten =
      folded
      |> String.split(" ", trim: true)
      |> Enum.map_join(" ", &Map.get(@word_synonyms, &1, &1))

    Enum.uniq([folded, rewritten]) |> Enum.reject(&(&1 == ""))
  end

  @doc "The folded query words worth a database prefilter (two letters on)."
  def query_words(query) do
    query
    |> query_variants()
    |> Enum.flat_map(&split_query/1)
    |> Enum.filter(&(String.length(&1) >= 2))
    |> Enum.uniq()
  end

  @doc """
  Scores `text` against `query` (best variant), or `nil` when a query word
  matches no word of the text. Per query word: prefix 10 (+3 for the whole
  word), inside a word 6, a typo 4 − distance.
  """
  def score(query, text) when is_binary(query) and is_binary(text) do
    words = text |> fold() |> split_text()

    query
    |> query_variants()
    |> Enum.map(&score_words(split_query(&1), words))
    |> Enum.reject(&is_nil/1)
    |> Enum.max(fn -> nil end)
  end

  def score(_query, _text), do: nil

  @doc "Best score of a document against the query: its name, or an alias one less."
  def document_score(query, %{name: name} = doc) do
    on_name = score(query, name)

    on_alias =
      doc
      |> Map.get(:aliases, [])
      |> Enum.map(&score(query, &1))
      |> Enum.reject(&is_nil/1)
      |> Enum.max(fn -> nil end)

    case {on_name, on_alias} do
      {nil, nil} -> nil
      {a, nil} -> a
      {nil, b} -> b - 1
      {a, b} -> max(a, b - 1)
    end
  end

  @doc """
  Ranks documents for a query, best first: score, then uses, then name.
  Documents that do not match are left out.
  """
  def rank(query, docs, limit) do
    docs
    |> Enum.flat_map(fn doc ->
      case document_score(query, doc) do
        nil -> []
        s -> [{s, doc}]
      end
    end)
    |> Enum.sort_by(fn {s, doc} -> {-s, -Map.get(doc, :uses_count, 0), fold(doc.name)} end)
    |> Enum.map(&elem(&1, 1))
    |> Enum.take(limit)
  end

  @doc """
  The answer's groups from per-source hit lists: in source order, a name
  only in the first group that has it, each group capped at `limit`, empty
  groups left out. Each item is `%{name, catalog_slug, hint, uses_count}`.
  """
  def group(%{} = hits, limit) do
    {groups, _seen} =
      Enum.reduce(@sources, {[], MapSet.new()}, fn source, {acc, seen} ->
        {items, seen} =
          hits
          |> Map.get(source, [])
          |> Enum.reduce({[], seen}, fn hit, {items, seen} ->
            key = fold(hit.name)

            if MapSet.member?(seen, key) or length(items) >= limit,
              do: {items, seen},
              else: {[item(source, hit) | items], MapSet.put(seen, key)}
          end)

        case items do
          [] -> {acc, seen}
          items -> {[%{source: source, items: Enum.reverse(items)} | acc], seen}
        end
      end)

    Enum.reverse(groups)
  end

  defp item(:palee, hit),
    do: %{name: hit.name, catalog_slug: hit.catalog_slug, hint: hit[:category], uses_count: 0}

  defp item(_source, hit),
    do: %{
      name: hit.name,
      catalog_slug: hit[:catalog_slug],
      hint: nil,
      uses_count: hit[:uses_count] || 0
    }

  defp score_words([], _words), do: nil

  defp score_words(query_words, words) do
    Enum.reduce_while(query_words, 0, fn qw, total ->
      case best_word(qw, words) do
        nil -> {:halt, nil}
        s -> {:cont, total + s}
      end
    end)
  end

  defp best_word(qw, words) do
    words
    |> Enum.map(&word_score(qw, &1))
    |> Enum.reject(&is_nil/1)
    |> Enum.max(fn -> nil end)
  end

  defp word_score(qw, w) do
    q_len = String.length(qw)

    cond do
      String.starts_with?(w, qw) ->
        if w == qw, do: 13, else: 10

      q_len > 1 and String.contains?(w, qw) ->
        6

      q_len >= 3 ->
        allow = if q_len >= 7, do: 2, else: 1
        dist = min(distance(qw, String.slice(w, 0, q_len)), distance(qw, w))
        if dist <= allow, do: 4 - dist

      true ->
        nil
    end
  end

  defp split_query(text), do: String.split(text, ~r/[\s\-\/]+/u, trim: true)
  defp split_text(text), do: String.split(text, ~r/[\s\-\/(),·]+/u, trim: true)

  @doc "Damerau–Levenshtein distance (optimal string alignment) between two strings."
  def distance(a, b) do
    a = String.graphemes(a) |> List.to_tuple()
    b = String.graphemes(b) |> List.to_tuple()
    la = tuple_size(a)
    lb = tuple_size(b)

    cond do
      la == 0 ->
        lb

      lb == 0 ->
        la

      true ->
        init = Map.new(0..lb, &{{0, &1}, &1})

        d =
          Enum.reduce(1..la, init, fn i, d ->
            Enum.reduce(0..lb, d, fn
              0, d ->
                Map.put(d, {i, 0}, i)

              j, d ->
                cost = if elem(a, i - 1) == elem(b, j - 1), do: 0, else: 1

                best =
                  Enum.min([d[{i - 1, j}] + 1, d[{i, j - 1}] + 1, d[{i - 1, j - 1}] + cost])

                best =
                  if i > 1 and j > 1 and elem(a, i - 1) == elem(b, j - 2) and
                       elem(a, i - 2) == elem(b, j - 1),
                     do: min(best, d[{i - 2, j - 2}] + 1),
                     else: best

                Map.put(d, {i, j}, best)
            end)
          end)

        d[{la, lb}]
    end
  end

  defp value(row, key) when is_map(row), do: Map.get(row, key) || Map.get(row, to_string(key))
  defp value(_row, _key), do: nil
end

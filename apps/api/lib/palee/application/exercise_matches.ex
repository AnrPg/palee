defmodule Palee.Application.ExerciseMatches do
  @moduledoc """
  ADR-570: before a free-text workout is published, the coach confirms the
  catalog exercises the matcher found in it, so its muscles and qualities
  can be computed.

  `list/2` reads the saved draft's editor document and returns:

    * every run of words that names a catalog exercise (exactly or fuzzily)
      and is not linked yet, unless the coach already rejected the same words
      in this workout; a match the box confirmed before
      (`exercise_match_memories`) comes `remembered: true`, to be offered
      already answered «Ναι»;
    * every link whose words, since it was made, no longer name its
      exercise (`kind: "changed"`), unless the coach confirmed those words
      already (`checked`).

  Nothing found is a normal outcome. The editor turns the answers into links
  in the document (a «Όχι» is a link without an exercise) and saves it;
  `decide/3` then updates the box's memory and folds what the suggestion
  gained into goals the coach already edited, only adding muscles or
  promoting their roles (`GrowEditedGoals`, ADR-671).
  """

  alias Palee.Anatomy
  alias Palee.Application.GrowEditedGoals
  alias Palee.Workouts
  alias Palee.Workouts.Domain.{ExerciseMatcher, FreeTextDocument, SectionedText}

  @max_decisions 200

  def list(context, workout_id) do
    with {:ok, workout} <- fetch_workout(context, workout_id) do
      parts = parts(workout)
      names = catalog_names()
      rejected = parts |> Enum.flat_map(&elem(&1, 1)) |> rejected_words()

      found =
        Enum.flat_map(parts, fn {section, lines} ->
          Enum.flat_map(lines, fn line ->
            linked? = fn {from, to} -> Enum.any?(line.links, &(&1.from < to and from < &1.to)) end

            line.text
            |> ExerciseMatcher.match_line(names, linked?)
            |> Enum.reject(&MapSet.member?(rejected, ExerciseMatcher.folded(&1.typed)))
            |> Enum.map(&Map.merge(&1, %{line: line.index, section: section}))
          end)
        end)

      memory =
        Workouts.exercise_match_memories(
          context,
          found |> Enum.map(&ExerciseMatcher.folded(&1.typed)) |> Enum.uniq()
        )

      matches =
        Enum.map(found, fn match ->
          present(
            match,
            Atom.to_string(match.kind),
            memory[ExerciseMatcher.folded(match.typed)] == match.exercise_ref
          )
        end)

      changed =
        Enum.flat_map(parts, fn {section, lines} -> changed_links(lines, names, section) end)

      {:ok, %{matches: matches ++ changed}}
    end
  end

  def decide(context, workout_id, params) do
    with {:ok, decisions} <- decisions(stringify(params)),
         {:ok, workout} <- fetch_workout(context, workout_id) do
      remember =
        for %{decision: "yes"} = d <- decisions, do: Map.take(d, [:folded, :exercise_ref])

      forget = for %{decision: "no"} = d <- decisions, do: Map.take(d, [:folded, :exercise_ref])

      :ok =
        Workouts.update_exercise_match_memories(
          context,
          remember,
          forget,
          context.user_id,
          DateTime.utc_now()
        )

      {:ok, %{goals_updated: GrowEditedGoals.call(context, workout)}}
    end
  end

  defp changed_links(lines, names, section) do
    for line <- lines,
        %{ref: ref} = link when is_binary(ref) <- line.links,
        ExerciseMatcher.folded(link.text) != link.checked,
        resolved_ref(ExerciseMatcher.resolve(link.text, names)) != ref,
        entry = Workouts.exercise_catalog_entry(ref),
        entry != nil do
      present(
        %{
          line: line.index,
          section: section,
          from: link.from,
          to: link.to,
          typed: link.text,
          exercise_ref: ref,
          label: entry.label
        },
        "changed",
        false
      )
    end
  end

  defp resolved_ref({ref, _kind}), do: ref
  defp resolved_ref(nil), do: nil

  defp present(match, kind, remembered) do
    targets = Anatomy.exercise_targets(match.exercise_ref) || %{muscles: [], qualities: []}

    section = Map.get(match, :section)

    %{
      id: Enum.join(Enum.reject([section, match.line, match.from, match.to], &is_nil/1), ":"),
      section: section,
      line: match.line,
      from: match.from,
      to: match.to,
      typed: match.typed,
      folded: ExerciseMatcher.folded(match.typed),
      exercise_ref: match.exercise_ref,
      label: match.label,
      kind: kind,
      remembered: remembered,
      muscles: Enum.map(targets.muscles, &%{id: &1.id, role: Atom.to_string(&1.role)}),
      qualities: targets.qualities
    }
  end

  defp rejected_words(lines) do
    for line <- lines,
        link <- line.links,
        is_nil(link.ref),
        into: MapSet.new(),
        do: ExerciseMatcher.folded(link.text)
  end

  defp catalog_names,
    do:
      ExerciseMatcher.names(
        Workouts.exercise_catalog_entries(),
        &Workouts.exercise_catalog_search_aliases/1
      )

  # The text the check reads, as `[{section, lines}]`. A sectioned draft
  # (ADR-180) keeps each section's text in its own document until publishing
  # composes them, so it is read section by section (`section` = its
  # 0-based place among the draft's sections, how the editor answers it,
  # ADR-671); any other workout is one document (`section` nil), the
  # coach's unpublished edit winning over the published text.
  defp parts(workout) do
    draft = workout_field(workout, :draft_data)

    case is_map(draft) and SectionedText.sectioned?(draft) and workout_field(draft, :sections) do
      [_ | _] = sections ->
        sections
        |> Enum.with_index()
        |> Enum.map(fn {section, index} ->
          {index, section |> SectionedText.section_document() |> FreeTextDocument.lines()}
        end)

      _single ->
        [{nil, workout |> document() |> FreeTextDocument.lines()}]
    end
  end

  defp document(workout) do
    workout_field(workout_field(workout, :draft_data), :free_text_document) ||
      workout_field(workout, :free_text_document)
  end

  defp workout_field(%{} = map, key), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))
  defp workout_field(_map, _key), do: nil

  defp decisions(%{"decisions" => list}) when is_list(list) and length(list) <= @max_decisions do
    list
    |> Enum.reduce_while({:ok, []}, fn
      %{"typed" => typed, "exercise_ref" => ref, "decision" => decision}, {:ok, acc}
      when is_binary(typed) and is_binary(ref) and decision in ["yes", "no"] ->
        folded = ExerciseMatcher.folded(typed)

        if folded == "" or String.length(folded) > 120 or
             is_nil(Workouts.exercise_catalog_entry(ref)),
           do: {:halt, {:error, :invalid_exercise_match_decision}},
           else: {:cont, {:ok, [%{folded: folded, exercise_ref: ref, decision: decision} | acc]}}

      _other, _acc ->
        {:halt, {:error, :invalid_exercise_match_decision}}
    end)
    |> case do
      {:ok, list} -> {:ok, Enum.reverse(list)}
      error -> error
    end
  end

  defp decisions(_params), do: {:error, :invalid_exercise_match_decision}

  defp stringify(%{} = map) when not is_struct(map),
    do: Map.new(map, fn {key, value} -> {to_string(key), stringify(value)} end)

  defp stringify(list) when is_list(list), do: Enum.map(list, &stringify/1)
  defp stringify(value), do: value

  defp fetch_workout(context, workout_id) do
    with {:ok, id} <- cast(workout_id),
         %{} = workout <- Workouts.get_workout_for_admin(context, id) do
      {:ok, workout}
    else
      _missing -> {:error, :not_found}
    end
  end

  defp cast(id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> {:ok, id}
      :error -> :error
    end
  end
end

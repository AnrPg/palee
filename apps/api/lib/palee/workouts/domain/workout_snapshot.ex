defmodule Palee.Workouts.Domain.WorkoutSnapshot do
  @moduledoc """
  ADR-357 (CP-D3): the content of a WOD frozen at the moment it was
  assigned or performed.

  `content/1` keeps only what the WOD *says* (title, type, text, sections,
  plans, exercises, scale notes, the body of ADR-224) and drops what only
  describes where it is kept (ids of the WOD and its folder, status, times,
  who created it). Two reads of an unchanged WOD give the same content, so
  `hash/1` (SHA-256 of a canonical encoding: JSON values, map keys sorted)
  lets the store keep one snapshot per distinct content.

  `@format_version` changes when `content/1` keeps a different set of
  fields; old snapshots keep the version they were written with.
  """

  @format_version 1

  @kept ~w(title subtitle description type is_team_workout difficulty
           estimated_duration_seconds equipment tags content workout_metadata
           authoring_mode icon sections body available_scale_levels)a

  # Inside sections and exercises: keys that only say where a row lives.
  # Section and exercise ids stay: results name their section by id.
  @volatile ~w(inserted_at updated_at workout_id master_workout_id section_id
               organization_id folder_id created_by_id lock_version)

  def format_version, do: @format_version

  @doc "The WOD's content as plain JSON values (string keys), without volatile keys."
  @spec content(map()) :: map()
  def content(workout) when is_map(workout) do
    workout
    |> Map.take(@kept ++ Enum.map(@kept, &Atom.to_string/1))
    |> to_json()
    |> strip()
  end

  @doc "Hex SHA-256 of the canonical form of `content`."
  @spec hash(map()) :: String.t()
  def hash(content) when is_map(content) do
    :sha256
    |> :crypto.hash(:erlang.term_to_binary(canonical(content), [:deterministic]))
    |> Base.encode16(case: :lower)
  end

  @doc "`%{content, content_hash, format_version, title}` ready to store."
  @spec build(map()) :: map()
  def build(workout) do
    content = content(workout)

    %{
      content: content,
      content_hash: hash(content),
      format_version: @format_version,
      title: Map.get(content, "title")
    }
  end

  @doc "Whether a later read of a WOD still says what a snapshot says."
  @spec same?(map(), map()) :: boolean()
  def same?(snapshot, workout), do: snapshot_hash(snapshot) == workout |> content() |> hash()

  defp snapshot_hash(%{content_hash: hash}), do: hash
  defp snapshot_hash(%{"content_hash" => hash}), do: hash

  defp to_json(term), do: term |> Jason.encode!() |> Jason.decode!()

  defp strip(map) when is_map(map) do
    map
    |> Map.drop(@volatile)
    |> Map.new(fn {key, value} -> {key, strip(value)} end)
  end

  defp strip(list) when is_list(list), do: Enum.map(list, &strip/1)
  defp strip(value), do: value

  # Maps become sorted key lists so the encoding does not depend on how
  # the runtime orders a large map.
  defp canonical(map) when is_map(map),
    do: map |> Enum.map(fn {k, v} -> {k, canonical(v)} end) |> Enum.sort()

  defp canonical(list) when is_list(list), do: Enum.map(list, &canonical/1)
  defp canonical(value), do: value
end

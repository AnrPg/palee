defmodule Palee.Execution.Domain.VaultFilter do
  @moduledoc """
  The Vault filter (ADR-162, vision §7.2): `disciplines` (workout types),
  `benchmark` (a benchmark slug, see `WorkoutIdentity`), `exercise` (a name,
  matched by substring after normalising), `sources` (provider ids,
  `freeform`, `device`) and `date_from` / `date_to` (inclusive). Versioned
  and stored like the other typed filters (ADR-151).
  """

  alias Palee.Execution.Domain.WorkoutIdentity
  alias Palee.Workouts.Domain.WorkoutType
  alias Palee.Identity.Domain.FilterFields

  @version 1
  @disciplines Palee.Workouts.Domain.WorkoutType.keys()

  defstruct version: @version,
            disciplines: [],
            benchmark: nil,
            exercise: nil,
            sources: [],
            date_from: nil,
            date_to: nil

  def disciplines, do: @disciplines

  def parse(nil), do: parse(%{})

  def parse(params) when is_map(params) do
    params = FilterFields.stringify(params)

    with :ok <- FilterFields.version(params["v"], @version),
         {:ok, disciplines} <-
           FilterFields.subset(:disciplines, params["disciplines"], @disciplines),
         {:ok, benchmark} <- benchmark(params["benchmark"]),
         {:ok, exercise} <- FilterFields.text(:exercise, params["exercise"], 2, 80),
         {:ok, sources} <- FilterFields.sources(:sources, params["sources"]),
         {:ok, {from, to}} <- FilterFields.date_range(params["date_from"], params["date_to"]) do
      {:ok,
       %__MODULE__{
         disciplines: disciplines,
         benchmark: benchmark,
         exercise: exercise,
         sources: sources,
         date_from: from,
         date_to: to
       }}
    end
  end

  def parse(_params), do: {:error, [filter: "must be an object"]}

  def to_params(%__MODULE__{} = filter) do
    %{
      "v" => filter.version,
      "disciplines" => filter.disciplines,
      "benchmark" => filter.benchmark,
      "exercise" => filter.exercise,
      "sources" => filter.sources,
      "date_from" => FilterFields.iso(filter.date_from),
      "date_to" => FilterFields.iso(filter.date_to)
    }
  end

  def active_count(%__MODULE__{} = filter) do
    [
      filter.disciplines != [],
      not is_nil(filter.benchmark),
      not is_nil(filter.exercise),
      filter.sources != [],
      not is_nil(filter.date_from) or not is_nil(filter.date_to)
    ]
    |> Enum.count(& &1)
  end

  @doc """
  Does one attempt pass? An attempt is `%{key, type, exercise_names,
  source_token, on}` (`on` the local date it was done).
  """
  def match?(%__MODULE__{} = filter, attempt) do
    discipline?(filter, attempt) and benchmark?(filter, attempt) and
      exercise?(filter.exercise, attempt.exercise_names) and
      source?(filter.sources, attempt.source_token) and
      in_range?(attempt.on, filter.date_from, filter.date_to)
  end

  @doc "Exercise names contain `exercise` (normalised substring)."
  def exercise?(nil, _names), do: true

  def exercise?(exercise, names) do
    needle = WorkoutIdentity.normalize(exercise)
    Enum.any?(List.wrap(names), &String.contains?(WorkoutIdentity.normalize(&1), needle))
  end

  def source?([], _token), do: true
  def source?(sources, token), do: token in sources

  def in_range?(_on, nil, nil), do: true
  def in_range?(nil, _from, _to), do: false

  def in_range?(on, from, to),
    do:
      (is_nil(from) or Date.compare(on, from) != :lt) and
        (is_nil(to) or Date.compare(on, to) != :gt)

  defp discipline?(%{disciplines: []}, _attempt), do: true
  # ADR-690: an attempt has one or more types (a box's own type reads as its
  # family); it passes when any of them is chosen, or is in a chosen kind's
  # family.
  defp discipline?(%{disciplines: list}, attempt) do
    types = attempt |> Map.get(:types) |> List.wrap() |> Enum.map(&to_string/1)

    types =
      if types == [],
        do: attempt |> Map.get(:type) |> List.wrap() |> Enum.map(&to_string/1),
        else: types

    chosen_families = list |> Enum.map(&WorkoutType.family/1) |> MapSet.new()

    Enum.any?(types, &(&1 in list)) or
      attempt
      |> Map.get(:families, [])
      |> List.wrap()
      |> Enum.any?(&(MapSet.member?(chosen_families, &1) and every_kind_of_family?(&1, list)))
  end

  # A box type joins a family filter only when the whole family was chosen
  # (the web sends a family as all of its kinds).
  defp every_kind_of_family?(family, list) do
    case Enum.find(WorkoutType.families(), &(elem(&1, 0) == family)) do
      {_family, kinds} -> Enum.all?(kinds, &(&1 in list))
      nil -> false
    end
  end

  defp benchmark?(%{benchmark: nil}, _attempt), do: true

  defp benchmark?(%{benchmark: slug}, attempt),
    do: WorkoutIdentity.key_benchmark(attempt.key || "") == slug

  defp benchmark(nil), do: {:ok, nil}
  defp benchmark(""), do: {:ok, nil}

  defp benchmark(value) when is_binary(value) do
    slug = value |> WorkoutIdentity.normalize() |> String.replace(" ", "_")
    if slug == "", do: {:ok, nil}, else: {:ok, slug}
  end

  defp benchmark(_value), do: {:error, [benchmark: "must be text"]}
end

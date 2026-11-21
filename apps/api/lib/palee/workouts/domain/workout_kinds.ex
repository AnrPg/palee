defmodule Palee.Workouts.Domain.WorkoutKinds do
  @moduledoc """
  A WOD's types as a set of references (ADR-690).

  A reference is either a Palee kind key (a built-in `WorkoutType` key or a
  kind the Palee team added, `workout_kind_additions.key`) or a box's own
  type, `box:<uuid>` (`organization_workout_kinds.id`). A WOD has one or more
  of them, none is "the main one", and every one belongs to a family, so
  stats, badges and colours read `families/2` and never look a box type up.

  The catalogue a function receives is the box's view of every kind:

      %{additions: [%{key, family}], box: [%{id, label, family, status, merged_into}]}

  Pure: the stores load the catalogue, this module decides.
  """

  alias Palee.Workouts.Domain.WorkoutType

  @box_prefix "box:"
  @key_format ~r/^[a-z][a-z0-9_]{1,47}$/
  @uuid_format ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/
  @max_label_length 40
  @statuses ~w(active hidden merged)

  @type catalogue :: %{additions: [map()], box: [map()]}

  def statuses, do: @statuses
  def max_label_length, do: @max_label_length
  def key_format, do: @key_format

  @doc "An empty catalogue: the built-in kinds only."
  def builtin_catalogue, do: %{additions: [], box: []}

  @doc "The reference of a box type."
  def box_ref(id) when is_binary(id), do: @box_prefix <> id

  @doc "The box type id of a reference, or nil for a Palee kind."
  def box_id(@box_prefix <> id), do: if(Regex.match?(@uuid_format, id), do: id)
  def box_id(_ref), do: nil

  def box_ref?(ref), do: is_binary(ref) and box_id(ref) != nil

  @doc "Is `ref` shaped like a reference (a key or a box reference)?"
  def ref_shape?(ref) when is_binary(ref), do: box_ref?(ref) or Regex.match?(@key_format, ref)
  def ref_shape?(_ref), do: false

  @doc "Folds a label: no accents or tonos, lowercase, final sigma, single spaces."
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

  @doc "A typed label, trimmed and single-spaced, or an error."
  def label(value) when is_binary(value) do
    label = value |> String.replace(~r/\s+/u, " ") |> String.trim()

    cond do
      String.length(label) < 2 -> {:error, :workout_kind_label_too_short}
      String.length(label) > @max_label_length -> {:error, :workout_kind_label_too_long}
      true -> {:ok, label}
    end
  end

  def label(_value), do: {:error, :workout_kind_label_too_short}

  @doc "Is `family` one of the nine families?"
  def family?(family), do: is_binary(family) and family in WorkoutType.family_keys()

  @doc """
  The family of a reference, or nil when the catalogue does not know it. A
  merged box type answers for the kind it was merged into.
  """
  def family(ref, catalogue \\ builtin_catalogue())

  def family(ref, catalogue) when is_binary(ref) do
    cond do
      family = WorkoutType.family(ref) -> family
      box_ref?(ref) -> box_family(box_id(ref), catalogue)
      true -> catalogue |> additions() |> Enum.find_value(&(&1.key == ref && &1.family))
    end
  end

  def family(_ref, _catalogue), do: nil

  defp box_family(id, catalogue) do
    case Enum.find(box(catalogue), &(&1.id == id)) do
      %{status: "merged", merged_into: target} when is_binary(target) ->
        family(target, %{catalogue | box: Enum.reject(box(catalogue), &(&1.id == id))})

      %{family: family} ->
        family

      nil ->
        nil
    end
  end

  @doc "The families of `refs`, each once, in catalogue order."
  def families(refs, catalogue \\ builtin_catalogue()) do
    chosen = refs |> List.wrap() |> Enum.map(&family(&1, catalogue)) |> MapSet.new()
    Enum.filter(WorkoutType.family_keys(), &MapSet.member?(chosen, &1))
  end

  @doc """
  Is `ref` a type a WOD of this box may have? `keep` are the WOD's current
  types: a hidden box type stays valid on a WOD that already has it.
  """
  def valid?(ref, catalogue, keep \\ []) do
    cond do
      not is_binary(ref) ->
        false

      WorkoutType.valid?(ref) ->
        true

      box_ref?(ref) ->
        case Enum.find(box(catalogue), &(&1.id == box_id(ref))) do
          %{status: "active"} -> true
          %{status: "hidden"} -> ref in keep
          _ -> false
        end

      true ->
        Enum.any?(additions(catalogue), &(&1.key == ref))
    end
  end

  @doc """
  Checks and orders a set of references: each once, built-in kinds in
  catalogue order, then additions by family and key, then box types by
  label. The order carries no meaning (there is no main type); it only keeps
  stored sets comparable.
  """
  def normalize(refs, catalogue, keep \\ []) do
    refs = refs |> List.wrap() |> Enum.map(&to_ref/1) |> Enum.reject(&(&1 in [nil, ""]))
    refs = Enum.map(refs, &resolve_merged(&1, catalogue))

    case Enum.reject(refs, &valid?(&1, catalogue, keep)) do
      [] -> {:ok, sort(Enum.uniq(refs), catalogue)}
      unknown -> {:error, {:unknown_workout_types, Enum.uniq(unknown)}}
    end
  end

  @doc "A merged box type's reference becomes the reference it was merged into."
  def resolve_merged(ref, catalogue, seen \\ []) do
    with id when is_binary(id) <- box_id(ref),
         %{status: "merged", merged_into: target} when is_binary(target) <-
           Enum.find(box(catalogue), &(&1.id == id)),
         false <- ref in seen do
      resolve_merged(target, catalogue, [ref | seen])
    else
      _ -> ref
    end
  end

  @doc "Orders references (see `normalize/3`)."
  def sort(refs, catalogue) do
    builtin_index = WorkoutType.keys() |> Enum.with_index() |> Map.new()
    family_index = WorkoutType.family_keys() |> Enum.with_index() |> Map.new()
    labels = Map.new(box(catalogue), &{box_ref(&1.id), fold(&1.label)})

    Enum.sort_by(refs, fn ref ->
      cond do
        Map.has_key?(builtin_index, ref) ->
          {0, builtin_index[ref], ""}

        box_ref?(ref) ->
          {2, 0, Map.get(labels, ref, ref)}

        true ->
          {1, Map.get(family_index, family(ref, catalogue), 99), ref}
      end
    end)
  end

  @doc """
  The compatibility `master_workouts.type`: the first built-in kind of the
  set, or nil. Not a main type: readers that show or count types read
  `types` and `families`.
  """
  def legacy_type(refs) do
    refs |> List.wrap() |> Enum.find(&WorkoutType.valid?/1)
  end

  @doc """
  The WOD's types from what was sent: sections that carry types decide
  (their union), otherwise the WOD's own `types` (or an old client's
  `type`).
  """
  def requested(top_types, top_type, section_types) do
    from_sections = section_types |> List.wrap() |> Enum.flat_map(&List.wrap/1) |> Enum.uniq()

    cond do
      from_sections != [] -> from_sections
      is_list(top_types) -> Enum.uniq(top_types)
      is_binary(top_type) and top_type != "" -> [top_type]
      not is_nil(top_type) and is_atom(top_type) -> [Atom.to_string(top_type)]
      true -> []
    end
  end

  @doc """
  Rewrites `from` to `to` in a set (a merge or a Palee decision), keeping
  every other reference; the result is ordered.
  """
  def rewrite(refs, from, to, catalogue) do
    refs
    |> List.wrap()
    |> Enum.map(&if(&1 == from, do: to, else: &1))
    |> Enum.uniq()
    |> sort(catalogue)
  end

  defp to_ref(ref) when is_binary(ref), do: String.trim(ref)
  defp to_ref(ref) when is_atom(ref) and not is_nil(ref), do: Atom.to_string(ref)
  defp to_ref(_ref), do: nil

  defp additions(catalogue), do: Map.get(catalogue, :additions, [])
  defp box(catalogue), do: Map.get(catalogue, :box, [])
end

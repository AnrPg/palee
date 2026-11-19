defmodule Palee.Anatomy.Domain.ProgrammeLoad do
  @moduledoc """
  «Φορτίο προγράμματος» (ADR-670): which muscle groups the WODs a class
  already did in a window aimed at, from the programme (the WODs' goals),
  never from what members logged.

  Input is one item per WOD done on a gym day (`%{on: Date, muscles:
  [%{id, role}]}`); the same WOD on the same day counts once. Each target
  rolls up to its group (a head to its group, as the goal summary does) and
  counts once per WOD with its strongest role there. Unknown ids and regions
  are left out.
  """

  alias Palee.Anatomy.Domain.MuscleTaxonomy

  @roles ["primary", "secondary", "stabilizer"]

  @type wod :: %{on: Date.t(), muscles: [%{id: String.t(), role: String.t() | atom()}]}
  @type group_load :: %{
          id: String.t(),
          wods: non_neg_integer(),
          primary: non_neg_integer(),
          secondary: non_neg_integer(),
          stabilizer: non_neg_integer(),
          dates: [Date.t()]
        }

  @doc """
  The groups the WODs hit, most WODs first (then primary count, then tree
  order), each with how many WODs per role and the days (ascending, distinct).
  """
  @spec build([wod]) :: [group_load]
  def build(wods) do
    wods
    |> Enum.flat_map(fn %{on: on, muscles: muscles} ->
      muscles
      |> strongest_by_group()
      |> Enum.map(fn {group, role} -> {group, role, on} end)
    end)
    |> Enum.group_by(fn {group, _role, _on} -> group end)
    |> Enum.map(fn {group, hits} -> group_load(group, hits) end)
    |> Enum.sort_by(&{-&1.wods, -&1.primary, MuscleTaxonomy.order(&1.id)})
  end

  defp strongest_by_group(muscles) do
    Enum.reduce(muscles, %{}, fn muscle, acc ->
      role = to_string(muscle.role)

      case {MuscleTaxonomy.group_of(muscle.id), role in @roles} do
        {group, true} when is_binary(group) ->
          Map.update(acc, group, role, &stronger(&1, role))

        _other ->
          acc
      end
    end)
  end

  defp stronger(a, b), do: if(rank(a) <= rank(b), do: a, else: b)
  defp rank(role), do: Enum.find_index(@roles, &(&1 == role))

  defp group_load(group, hits) do
    roles = Enum.frequencies_by(hits, fn {_group, role, _on} -> role end)

    %{
      id: group,
      wods: length(hits),
      primary: Map.get(roles, "primary", 0),
      secondary: Map.get(roles, "secondary", 0),
      stabilizer: Map.get(roles, "stabilizer", 0),
      dates: hits |> Enum.map(fn {_group, _role, on} -> on end) |> Enum.uniq() |> Enum.sort(Date)
    }
  end
end

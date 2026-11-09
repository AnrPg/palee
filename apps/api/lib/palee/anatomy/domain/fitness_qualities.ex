defmodule Palee.Anatomy.Domain.FitnessQualities do
  @moduledoc """
  The ten general physical skills used by WOD goals and the qualities radar
  (ADR-163, brief §7.6). ADR-560: they live in the `fitness_qualities`
  reference table. Ids are stable; labels are translated on the client
  (`anatomy.quality.<id>`).
  """

  def all, do: Palee.Catalog.reference().qualities

  def known?(id), do: id in all()

  @doc "Keeps known qualities, in canonical order, without duplicates."
  def normalize(ids) when is_list(ids) do
    wanted = MapSet.new(ids)
    Enum.filter(all(), &MapSet.member?(wanted, &1))
  end

  def normalize(_ids), do: []
end

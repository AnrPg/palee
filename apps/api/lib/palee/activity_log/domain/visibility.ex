defmodule Palee.ActivityLog.Domain.Visibility do
  @moduledoc """
  ADR-760 (ANR 4A): who reads which part of the «Αρχείο ενεργειών». Each
  area has its own capability (`view_activity_<area>`), so a box can widen
  a role the usual way (ADR-099). By default the owner and admins read
  every area, the accountant money, packages and staff pay, the front desk
  members, money, packages and classes, and coaches the classes. Staff pay
  read with the `:own` scope (every staff role) shows only the rows about
  the reader themselves.

  The member never reads this module's areas: they see only the rows staff
  chose to share with them (5A), through `ActivityLog.list_for_member/1`.
  """

  alias Palee.ActivityLog.Domain.Actions

  @export :export_activity_log

  def capability(area) when is_atom(area), do: :"view_activity_#{area}"
  def capabilities, do: Enum.map(Actions.areas(), &capability/1)
  def export_capability, do: @export

  @doc """
  What a reader may see, from their capabilities (`%{capability => scope}`):
  `%{all: [area], own: [area]}`. An area read only with `:own` shows the
  rows whose person is the reader.
  """
  def readable(capabilities) when is_map(capabilities) do
    Enum.reduce(Actions.areas(), %{all: [], own: []}, fn area, acc ->
      case Map.get(capabilities, capability(area)) do
        :all -> %{acc | all: acc.all ++ [area]}
        scope when scope in [:own, :status] -> %{acc | own: acc.own ++ [area]}
        nil -> acc
      end
    end)
  end

  def readable(_capabilities), do: %{all: [], own: []}

  def any?(capabilities), do: readable(capabilities) != %{all: [], own: []}

  def can_export?(capabilities) when is_map(capabilities),
    do: Map.get(capabilities, @export) == :all

  def can_export?(_capabilities), do: false
end

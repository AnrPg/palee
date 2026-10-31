defmodule PaleeWeb.Growth.Params do
  @moduledoc """
  Request bodies of the leads, automations and at-risk endpoints (ADR-344..347)
  as the application services read them: string keys at every level, cast
  values (dates, times) kept as they are.
  """

  def stringify(%_{} = struct), do: struct

  def stringify(map) when is_map(map),
    do: Map.new(map, fn {key, value} -> {to_string(key), stringify(value)} end)

  def stringify(list) when is_list(list), do: Enum.map(list, &stringify/1)
  def stringify(value), do: value
end

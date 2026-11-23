defmodule Palee.ActivityLog.Csv do
  @moduledoc """
  ADR-760 (10A): the «Αρχείο ενεργειών» as CSV, one row per entry, for
  the owner, admins and the accountant. Column names are stable English
  keys (a spreadsheet's columns, not screen text); the action is its key.
  Cells that a spreadsheet would run as a formula are prefixed with `'`.
  """

  @columns ~w(occurred_at action area actor actor_roles person subject reason shared_with_member changes)

  def encode(entries) when is_list(entries) do
    rows = Enum.map(entries, &row/1)
    [@columns | rows] |> Enum.map_join("\r\n", &line/1) |> Kernel.<>("\r\n")
  end

  defp row(entry) do
    [
      DateTime.to_iso8601(entry.occurred_at),
      entry.action,
      entry.area,
      get_in(entry, [:actor, :name]) || "",
      entry |> get_in([:actor, :roles]) |> List.wrap() |> Enum.join(" "),
      get_in(entry, [:person, :name]) || "",
      entry.subject_label || "",
      entry.reason || "",
      to_string(entry[:reason_shared] == true),
      changes(entry.details)
    ]
  end

  defp changes(%{"changes" => changes}) when is_list(changes),
    do: Enum.map_join(changes, "; ", &change/1)

  defp changes(%{changes: changes}) when is_list(changes),
    do: Enum.map_join(changes, "; ", &change/1)

  defp changes(_details), do: ""

  defp change(change) do
    field = change["field"] || change[:field]
    before = change["before"] || change[:before]
    after_value = change["after"] || change[:after]
    "#{field}: #{before} -> #{after_value}"
  end

  defp line(cells), do: Enum.map_join(cells, ",", &cell/1)

  defp cell(value) do
    text = value |> to_string() |> guard_formula()

    if String.contains?(text, [",", "\"", "\n", "\r"]),
      do: "\"" <> String.replace(text, "\"", "\"\"") <> "\"",
      else: text
  end

  defp guard_formula(<<first, _rest::binary>> = text) when first in [?=, ?+, ?-, ?@, ?\t, ?\r],
    do: "'" <> text

  defp guard_formula(text), do: text
end

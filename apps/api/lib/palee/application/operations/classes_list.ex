defmodule Palee.Application.Operations.ClassesList do
  @moduledoc "ADR-378 `classes.list`: the schedule between two times."

  @behaviour Palee.Operations.Operation

  alias Palee.Application.Operations.Views
  alias Palee.Scheduling

  @max_days 31

  @impl true
  def spec do
    %{
      name: "classes.list",
      kind: :query,
      summary: "List classes in a period",
      description:
        "Classes that start from `from` (inclusive) to `to` (exclusive), at most 31 days " <>
          "apart, oldest first, including cancelled ones (status). Times are UTC.",
      capability: [:manage_schedule, :run_classes, :book_for_clients],
      scope: "classes:read",
      risk: :read,
      data_classes: [],
      http: %{method: :get, path: "/classes"},
      input: %{
        "type" => "object",
        "additionalProperties" => false,
        "properties" => %{
          "from" => Views.date_time(),
          "to" => Views.date_time(),
          "location_id" => Views.uuid()
        },
        "required" => ["from", "to"]
      },
      output: %{
        "type" => "object",
        "properties" => %{"data" => %{"type" => "array", "items" => Views.class_schema()}},
        "required" => ["data"]
      },
      examples: [
        %{input: %{"from" => "2026-11-02T00:00:00Z", "to" => "2026-11-09T00:00:00Z"}, output: %{}}
      ]
    }
  end

  @impl true
  def execute(context, input) do
    {:ok, from, _} = DateTime.from_iso8601(input["from"])
    {:ok, to, _} = DateTime.from_iso8601(input["to"])

    cond do
      DateTime.compare(to, from) != :gt ->
        {:error, {:invalid_fields, %{"to" => ["must be after from"]}}}

      DateTime.diff(to, from, :day) > @max_days ->
        {:error, {:invalid_fields, %{"to" => ["must be at most #{@max_days} days after from"]}}}

      true ->
        slots =
          context
          |> Scheduling.get_calendar_week(%{
            start_at: from,
            end_at: to,
            class_type_ids: [],
            include_drafts: true
          })
          |> Enum.filter(
            &(is_nil(input["location_id"]) or Map.get(&1, :location_id) == input["location_id"])
          )

        {:ok, %{"data" => Enum.map(slots, &Views.class/1)}}
    end
  end
end

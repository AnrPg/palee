defmodule Palee.Application.Operations.ClassesGet do
  @moduledoc "ADR-378 `classes.get`: one class."

  @behaviour Palee.Operations.Operation

  alias Palee.Application.Operations.Views
  alias Palee.Scheduling

  @impl true
  def spec do
    %{
      name: "classes.get",
      kind: :query,
      summary: "Get one class",
      description: "A class by id (the `class_id` webhooks carry), with how many are booked.",
      capability: [:manage_schedule, :run_classes, :book_for_clients],
      scope: "classes:read",
      risk: :read,
      data_classes: [],
      http: %{method: :get, path: "/classes/{id}"},
      input: %{
        "type" => "object",
        "additionalProperties" => false,
        "properties" => %{"id" => Views.uuid()},
        "required" => ["id"]
      },
      output: Views.class_schema(),
      examples: [%{input: %{"id" => "0f8e3c2a-5b1d-4a7e-9c3f-1d2e3f4a5b6c"}, output: %{}}]
    }
  end

  @impl true
  def execute(context, %{"id" => id}) do
    case Scheduling.get_slot(context, id) do
      nil -> {:error, :not_found}
      slot -> {:ok, Views.class(slot)}
    end
  end
end

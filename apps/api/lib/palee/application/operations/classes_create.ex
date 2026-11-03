defmodule Palee.Application.Operations.ClassesCreate do
  @moduledoc "ADR-378 `classes.create`: adds one class (wraps `CreateScheduledSlot`)."

  @behaviour Palee.Operations.Operation

  alias Palee.Application.CreateScheduledSlot
  alias Palee.Application.Operations.Views
  alias Palee.Scheduling

  @impl true
  def spec do
    %{
      name: "classes.create",
      kind: :command,
      summary: "Add a class to the schedule",
      description:
        "One class of an existing class type at a future time. Without a WOD it is a draft " <>
          "that only staff see until a WOD is linked in Palee (ADR-176). Use the box's own " <>
          "screens for weekly series. Undo by cancelling the class in Palee.",
      capability: [:manage_schedule],
      scope: "classes:write",
      risk: :write_reversible,
      data_classes: [],
      http: %{method: :post, path: "/classes", status: 201},
      input: %{
        "type" => "object",
        "additionalProperties" => false,
        "properties" => %{
          "class_type_id" => Views.uuid(),
          "name" => %{"type" => "string", "minLength" => 1, "maxLength" => 120},
          "starts_at" => Views.date_time(),
          "duration_minutes" => %{"type" => "integer", "minimum" => 5, "maximum" => 1440},
          "capacity" => %{"type" => "integer", "minimum" => 1, "maximum" => 500},
          "location_id" => Views.uuid(),
          "coach_id" => Views.uuid()
        },
        "required" => ["capacity", "class_type_id", "duration_minutes", "starts_at"]
      },
      output: Views.class_schema(),
      examples: [
        %{
          input: %{
            "class_type_id" => "0f8e3c2a-5b1d-4a7e-9c3f-1d2e3f4a5b6c",
            "starts_at" => "2026-11-10T17:00:00Z",
            "duration_minutes" => 60,
            "capacity" => 12
          },
          output: %{}
        }
      ]
    }
  end

  @impl true
  def preview(context, input) do
    case Scheduling.get_class_type(context, input["class_type_id"]) do
      nil ->
        {:error, :not_found}

      class_type ->
        {:ok,
         %{
           "would" => "add a class",
           "class" => Map.put(input, "name", input["name"] || class_type.name)
         }}
    end
  end

  @impl true
  def execute(context, input) do
    with %{} = class_type <-
           Scheduling.get_class_type(context, input["class_type_id"]) || {:error, :not_found},
         {:ok, slot} <-
           CreateScheduledSlot.call(context, %{
             class_type_id: class_type.id,
             name: input["name"] || class_type.name,
             scheduled_at: input["starts_at"],
             duration_minutes: input["duration_minutes"],
             capacity: input["capacity"],
             location_id: input["location_id"],
             coach_user_id: input["coach_id"],
             auto_approve: true
           }) do
      {:ok, Views.class(slot)}
    end
  end
end

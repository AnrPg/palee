defmodule PaleeWeb.WorkoutSnapshotController do
  @moduledoc "ADR-357 (CP-D3): a WOD as it was when it was assigned or performed."

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Palee.Application.WorkoutSnapshots
  alias PaleeWeb.Schemas.TrainingFloor, as: S
  alias OpenApiSpex.{Parameter, Schema}

  action_fallback PaleeWeb.FallbackController

  tags(["Workouts"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  operation(:show,
    summary: "A WOD snapshot (staff who program or follow training, or its own athlete)",
    parameters: [
      %Parameter{
        name: :id,
        in: :path,
        required: true,
        schema: %Schema{type: :string, format: :uuid}
      }
    ],
    responses: [
      ok: {"Snapshot", "application/json", S.workout_snapshot()},
      not_found: {"No such snapshot, or not yours", "application/json", S.error()}
    ]
  )

  def show(conn, %{id: id}) do
    with {:ok, snapshot} <- WorkoutSnapshots.get(conn.assigns.tenant_context, id),
         do: json(conn, %{snapshot: snapshot})
  end

  @holder_id %Parameter{
    name: :id,
    in: :path,
    required: true,
    schema: %Schema{type: :string, format: :uuid}
  }

  operation(:execution,
    summary: "The WOD as my own run performed it, and whether it changed since (ADR-389)",
    parameters: [@holder_id],
    responses: [
      ok: {"As performed", "application/json", S.workout_as_performed()},
      not_found: {"No such run, or not yours", "application/json", S.error()}
    ]
  )

  def execution(conn, %{id: id}), do: as_performed(conn, :execution, id)

  operation(:training_log,
    summary: "The WOD as my own logged score performed it, and whether it changed since (ADR-389)",
    parameters: [@holder_id],
    responses: [
      ok: {"As performed", "application/json", S.workout_as_performed()},
      not_found: {"No such score, or not yours", "application/json", S.error()}
    ]
  )

  def training_log(conn, %{id: id}), do: as_performed(conn, :training_log, id)

  defp as_performed(conn, holder, id) do
    with {:ok, result} <- WorkoutSnapshots.as_performed(conn.assigns.tenant_context, holder, id),
         do: json(conn, result)
  end
end

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
end

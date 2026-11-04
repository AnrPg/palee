defmodule PaleeWeb.ExecutionPacerController do
  @moduledoc "«Ο προηγούμενος εαυτός σου» on the person's own execution (ADR-374, CP-D7)."

  use PaleeWeb, :controller
  use PaleeWeb.ControllerSpecs

  alias OpenApiSpex.{Parameter, Schema}
  alias Palee.Application.ExecutionPacer
  alias PaleeWeb.Schemas.Pacer, as: S

  action_fallback PaleeWeb.FallbackController

  tags(["Executions"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  @id %Parameter{
    name: :id,
    in: :path,
    required: true,
    schema: %Schema{type: :string, format: :uuid}
  }

  operation(:splits,
    summary: "Record split marks (segment ends and rounds); repeats are ignored",
    parameters: [@id],
    request_body: S.body(S.splits_request()),
    responses: [
      ok: {"Stored", "application/json", S.splits_response()},
      not_found: {"Not your execution", "application/json", S.error()},
      unprocessable_entity: {"Marks don't fit the timer", "application/json", S.error()}
    ]
  )

  def splits(conn, %{id: id}) do
    with {:ok, result} <-
           ExecutionPacer.record_splits(conn.assigns.user_context, id, conn.body_params),
         do: json(conn, result)
  end

  operation(:show,
    summary: "The previous attempt at the same WOD or benchmark as a pace line beside this one",
    parameters: [@id],
    responses: [
      ok: {"Pace line", "application/json", S.pacer_response()},
      not_found: {"Not your execution", "application/json", S.error()}
    ]
  )

  def show(conn, %{id: id}) do
    with {:ok, pacer} <- ExecutionPacer.show(conn.assigns.user_context, id),
         do: json(conn, %{pacer: pacer})
  end
end

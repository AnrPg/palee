defmodule PaleeWeb.FitnessProfileController do
  @moduledoc "ADR-358 (CP-D6): the person's own fitness profile in the Journal."

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Palee.Application.GetFitnessProfile
  alias PaleeWeb.Schemas.TrainingFloor, as: S
  alias OpenApiSpex.Schema

  action_fallback PaleeWeb.FallbackController

  tags(["Progress"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  operation(:show,
    summary: "Your fitness score per domain, its reasoning and what to work on",
    parameters: [
      division: [
        in: :query,
        required: false,
        description: "Standards to read the PRs with (neutral mean when absent)",
        schema: %Schema{type: :string, enum: ~w(women men)}
      ]
    ],
    responses: [
      ok: {"Fitness profile", "application/json", S.fitness_profile()},
      unprocessable_entity: {"Unknown division", "application/json", S.error()}
    ]
  )

  def show(conn, params) do
    with {:ok, profile} <- GetFitnessProfile.call(conn.assigns.user_context, params),
         do: json(conn, profile)
  end
end

defmodule PaleeWeb.FitnessProfileController do
  @moduledoc """
  ADR-358 (CP-D6): the person's own fitness profile in the Journal; ADR-395
  adds the period's change and the person's own settings for the card.
  """

  use PaleeWeb, :controller
  use PaleeWeb.ControllerSpecs

  alias Palee.Application.{GetFitnessProfile, ManageFitnessSettings}
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
      ],
      period: [
        in: :query,
        required: false,
        description: "ADR-395: Πρόοδος's period; adds each domain's change since its start",
        schema: %Schema{type: :string, enum: ~w(4w 12w 6m 1y all)}
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

  operation(:settings,
    summary: "Your settings for the fitness card: body weight, birth year, what it shows",
    responses: [ok: {"Settings", "application/json", S.fitness_settings()}]
  )

  def settings(conn, _params) do
    with {:ok, settings} <- ManageFitnessSettings.get(conn.assigns.user_context),
         do: json(conn, settings)
  end

  operation(:update_settings,
    summary: "Change your settings for the fitness card (only the fields sent change)",
    request_body: S.body(S.fitness_settings_request()),
    responses: [
      ok: {"Settings", "application/json", S.fitness_settings()},
      unprocessable_entity: {"A value out of range", "application/json", S.error()}
    ]
  )

  def update_settings(conn, _params) do
    with {:ok, settings} <-
           ManageFitnessSettings.put(conn.assigns.user_context, conn.body_params),
         do: json(conn, settings)
  end
end

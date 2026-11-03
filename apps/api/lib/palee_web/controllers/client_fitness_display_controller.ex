defmodule PaleeWeb.ClientFitnessDisplayController do
  @moduledoc """
  ADR-395: a coach and the fitness card of a client they coach: the client's
  body weight, birth year and own choice, and what the card shows for them
  in this box.
  """

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Palee.Application.ClientFitnessDisplay
  alias PaleeWeb.Schemas.TrainingFloor, as: S
  alias OpenApiSpex.{Parameter, Schema}

  action_fallback PaleeWeb.FallbackController

  tags(["Progress"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  @client %Parameter{
    name: :user_id,
    in: :path,
    required: true,
    schema: %Schema{type: :string, format: :uuid}
  }

  operation(:show,
    summary: "A client's fitness card settings (only for their coach)",
    parameters: [@client],
    responses: [
      ok: {"Settings", "application/json", S.client_fitness_display()},
      forbidden: {"Not one of your clients", "application/json", S.error()}
    ]
  )

  def show(conn, %{user_id: user_id}) do
    with {:ok, view} <- ClientFitnessDisplay.get(conn.assigns.tenant_context, user_id),
         do: json(conn, view)
  end

  operation(:update,
    summary: "Choose what a client's fitness card shows (progress only, nothing, or theirs)",
    parameters: [@client],
    request_body: S.body(S.client_fitness_display_request()),
    responses: [
      ok: {"Settings", "application/json", S.client_fitness_display()},
      forbidden: {"Not one of your clients", "application/json", S.error()},
      unprocessable_entity: {"Unknown choice", "application/json", S.error()}
    ]
  )

  def update(conn, %{user_id: user_id}) do
    display = Map.get(conn.body_params, :display)

    with {:ok, view} <- ClientFitnessDisplay.put(conn.assigns.tenant_context, user_id, display),
         do: json(conn, view)
  end
end

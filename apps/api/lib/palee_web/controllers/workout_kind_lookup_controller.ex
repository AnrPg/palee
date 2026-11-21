defmodule PaleeWeb.WorkoutKindLookupController do
  @moduledoc """
  ADR-690: names workout types for any signed-in reader: the Palee team's
  additions and the box types among `refs` (a member's journal and the
  Vault hold types of several boxes).
  """

  use PaleeWeb, :controller
  use PaleeWeb.ControllerSpecs

  alias Palee.Application.WorkoutKinds
  alias OpenApiSpex.{Parameter, Schema}
  alias PaleeWeb.Schemas.WorkoutKinds, as: KindSchemas

  tags(["Workouts"])
  security([%{"bearerAuth" => []}])

  operation(:index,
    summary: "Labels and families of workout type references",
    parameters: [
      %Parameter{
        name: :refs,
        in: :query,
        required: false,
        schema: %Schema{type: :string, maxLength: 12_000},
        description: "Comma-separated references (`box:<id>` are looked up; at most 200)"
      }
    ],
    responses: [ok: {"Catalogue", "application/json", KindSchemas.catalogue()}]
  )

  def index(conn, params) do
    refs =
      (params["refs"] || "")
      |> String.split(",", trim: true)
      |> Enum.map(&String.trim/1)

    conn
    |> put_resp_header("cache-control", "private, max-age=300")
    |> json(KindSchemas.render_catalogue(WorkoutKinds.lookup(refs)))
  end
end

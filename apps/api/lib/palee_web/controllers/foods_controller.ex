defmodule PaleeWeb.FoodsController do
  @moduledoc "«Σάρωση barcode» and «Δικά μου τρόφιμα» in meals (ADR-376, CP-D9)."

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias OpenApiSpex.{Parameter, Schema}
  alias Palee.Application.Foods
  alias PaleeWeb.Schemas.Foods, as: S

  action_fallback PaleeWeb.FallbackController

  tags(["Foods"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  @id %Parameter{
    name: :id,
    in: :path,
    required: true,
    schema: %Schema{type: :string, format: :uuid}
  }

  operation(:barcode,
    summary: "Look a scanned barcode up: own foods, then Open Food Facts; else the manual entry",
    parameters: [
      %Parameter{
        name: :barcode,
        in: :path,
        required: true,
        schema: %Schema{type: :string, maxLength: 20}
      },
      %Parameter{
        name: :language,
        in: :query,
        required: false,
        schema: %Schema{type: :string, maxLength: 5}
      }
    ],
    responses: [
      ok: {"Lookup", "application/json", S.barcode_response()},
      unprocessable_entity: {"Not a valid barcode", "application/json", S.error()}
    ]
  )

  def barcode(conn, %{barcode: barcode} = params) do
    with {:ok, result} <-
           Foods.barcode(conn.assigns.user_context, barcode, Map.get(params, :language) || "el"),
         do: json(conn, result)
  end

  operation(:index,
    summary: "The person's own foods",
    responses: [ok: {"Own foods", "application/json", S.foods_response()}]
  )

  def index(conn, _params) do
    with {:ok, result} <- Foods.list(conn.assigns.user_context), do: json(conn, result)
  end

  operation(:create,
    summary: "Write down a food (the manual entry after a scan, or any time)",
    request_body: S.body(S.custom_food_create_request()),
    responses: [
      created: {"Own food", "application/json", S.food_response()},
      unprocessable_entity: {"Invalid", "application/json", S.error()}
    ]
  )

  def create(conn, _params) do
    with {:ok, food} <- Foods.create(conn.assigns.user_context, conn.body_params) do
      conn |> put_status(:created) |> json(%{food: food})
    end
  end

  operation(:update,
    summary: "Change an own food",
    parameters: [@id],
    request_body: S.body(S.custom_food_request()),
    responses: [
      ok: {"Own food", "application/json", S.food_response()},
      not_found: {"No such food", "application/json", S.error()},
      unprocessable_entity: {"Invalid", "application/json", S.error()}
    ]
  )

  def update(conn, %{id: id}) do
    with {:ok, food} <- Foods.update(conn.assigns.user_context, id, conn.body_params),
         do: json(conn, %{food: food})
  end

  operation(:delete,
    summary: "Delete an own food (meals that named it keep the name)",
    parameters: [@id],
    responses: [
      no_content: "Deleted",
      not_found: {"No such food", "application/json", S.error()}
    ]
  )

  def delete(conn, %{id: id}) do
    with :ok <- Foods.delete(conn.assigns.user_context, id), do: send_resp(conn, :no_content, "")
  end
end

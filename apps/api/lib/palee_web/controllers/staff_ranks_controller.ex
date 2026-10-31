defmodule PaleeWeb.StaffRanksController do
  @moduledoc "A client's belts and levels for their coach: standing, promotion, withdrawal, diploma (ADR-377)."

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Guardian.Plug, as: GuardianPlug
  alias OpenApiSpex.{Parameter, Schema}
  alias Palee.Application.RankPromotions
  alias PaleeWeb.Schemas.Ranks, as: S

  action_fallback PaleeWeb.FallbackController

  tags(["Ranks"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  @user_id %Parameter{
    name: :user_id,
    in: :path,
    required: true,
    schema: %Schema{type: :string, format: :uuid}
  }
  @id %Parameter{name: :id, in: :path, required: true, schema: %Schema{type: :string, format: :uuid}}

  operation(:client,
    summary: "A client's rank on each ladder, progress to the next and history",
    parameters: [@user_id],
    responses: [
      ok: {"Standing", "application/json", S.standings_response()},
      forbidden: {"Not your client", "application/json", S.error()}
    ]
  )

  def client(conn, %{user_id: user_id}) do
    with {:ok, result} <- RankPromotions.client(conn.assigns.tenant_context, user_id),
         do: json(conn, result)
  end

  operation(:award,
    summary: "Promote a client, or add a stripe, ticking the skills shown",
    parameters: [@user_id],
    request_body: S.body(S.award_request()),
    responses: [
      created: {"Award", "application/json", S.award_response()},
      forbidden: {"Not your client", "application/json", S.error()},
      unprocessable_entity: {"Not a step up, or invalid", "application/json", S.error()}
    ]
  )

  def award(conn, %{user_id: user_id}) do
    staff = GuardianPlug.current_resource(conn)

    with {:ok, award} <-
           RankPromotions.award(conn.assigns.tenant_context, staff.id, user_id, conn.body_params) do
      conn |> put_status(:created) |> json(%{award: award})
    end
  end

  operation(:revoke,
    summary: "Withdraw an award with a reason; it stays in the history",
    parameters: [@id],
    request_body: S.body(S.revoke_request()),
    responses: [
      ok: {"Award", "application/json", S.award_response()},
      not_found: {"No such award", "application/json", S.error()},
      conflict: {"Already withdrawn", "application/json", S.error()}
    ]
  )

  def revoke(conn, %{id: id}) do
    staff = GuardianPlug.current_resource(conn)

    with {:ok, award} <-
           RankPromotions.revoke(conn.assigns.tenant_context, staff.id, id, conn.body_params),
         do: json(conn, %{award: award})
  end

  operation(:certificate,
    summary: "The award's diploma as a PDF",
    parameters: [@id],
    responses: [
      ok: {"PDF", "application/pdf", S.pdf()},
      not_found: {"No such award", "application/json", S.error()}
    ]
  )

  def certificate(conn, %{id: id}) do
    with {:ok, %{filename: filename, data: data}} <-
           RankPromotions.certificate(conn.assigns.tenant_context, id) do
      send_download(conn, {:binary, data}, filename: filename, content_type: "application/pdf")
    end
  end
end

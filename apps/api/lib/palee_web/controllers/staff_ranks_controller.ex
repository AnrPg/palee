defmodule PaleeWeb.StaffRanksController do
  @moduledoc "A client's belts and levels for their coach: standing, promotion, withdrawal, diploma (ADR-377)."

  use PaleeWeb, :controller
  use PaleeWeb.ControllerSpecs

  alias Guardian.Plug, as: GuardianPlug
  alias OpenApiSpex.{Parameter, Schema}
  alias Palee.Application.{RankPromotions, RankReadyList, RankSkillTicks}
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
  @id %Parameter{
    name: :id,
    in: :path,
    required: true,
    schema: %Schema{type: :string, format: :uuid}
  }

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

  operation(:check_skill,
    summary: "Tick or untick one skill of a rank for a client, between promotions (ADR-400)",
    parameters: [@user_id],
    request_body: S.body(S.skill_check_request()),
    responses: [
      ok: {"Standing", "application/json", S.standings_response()},
      forbidden: {"Not your client", "application/json", S.error()},
      unprocessable_entity: {"Not a skill of that rank", "application/json", S.error()}
    ]
  )

  def check_skill(conn, %{user_id: user_id}) do
    staff = GuardianPlug.current_resource(conn)

    with {:ok, result} <-
           RankPromotions.check_skill(
             conn.assigns.tenant_context,
             staff.id,
             user_id,
             conn.body_params
           ),
         do: json(conn, result)
  end

  operation(:class_skills,
    summary:
      "The ladders' skills and, for each person of a class, what they work towards and have ticked",
    parameters: [
      user_ids: [
        in: :query,
        required: true,
        description: "Comma-separated user ids (up to 100)",
        schema: %Schema{type: :string, minLength: 1}
      ]
    ],
    responses: [
      ok: {"Class skills", "application/json", S.class_skills_response()},
      forbidden: {"No coaching", "application/json", S.error()}
    ]
  )

  def class_skills(conn, %{user_ids: user_ids}) do
    with {:ok, result} <- RankSkillTicks.class_view(conn.assigns.tenant_context, user_ids),
         do: json(conn, result)
  end

  operation(:batch_skills,
    summary: "Tick or untick one skill for several people at once (a class)",
    request_body: S.body(S.batch_check_request()),
    responses: [
      ok: {"Who changed and who was skipped", "application/json", S.batch_check_response()},
      forbidden: {"No coaching", "application/json", S.error()},
      unprocessable_entity: {"Not a skill of that rank", "application/json", S.error()}
    ]
  )

  def batch_skills(conn, _params) do
    staff = GuardianPlug.current_resource(conn)

    with {:ok, result} <-
           RankSkillTicks.batch(conn.assigns.tenant_context, staff.id, conn.body_params),
         do: json(conn, result)
  end

  operation(:ready,
    summary: "People who meet what their ladder counts for the next rank (the coach decides)",
    responses: [
      ok: {"Ready", "application/json", S.ready_response()},
      forbidden: {"No coaching", "application/json", S.error()}
    ]
  )

  def ready(conn, _params) do
    with {:ok, result} <- RankReadyList.call(conn.assigns.tenant_context), do: json(conn, result)
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

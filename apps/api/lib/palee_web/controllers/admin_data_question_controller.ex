defmodule PaleeWeb.AdminDataQuestionController do
  @moduledoc """
  ADR-361 (CP-F4): staff ask questions over their box's data in plain
  words. Read-only, the asker's own rights, answers citing the numbers;
  every question is in the box's audit log (owners and admins see all).
  """

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias OpenApiSpex.{Parameter, Schema}
  alias Palee.Application.DataQuestions.DataQuestions
  alias PaleeWeb.Schemas.AiHelp, as: S

  action_fallback PaleeWeb.FallbackController

  tags(["Data questions"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  @slug %Parameter{name: :organization_slug, in: :path, required: false, schema: %Schema{type: :string}}

  operation(:catalogue,
    summary: "What this person can ask: the switch, the read queries and the daily limit",
    parameters: [@slug],
    responses: [ok: {"Catalogue", "application/json", S.data_catalogue()}]
  )

  def catalogue(conn, _params) do
    with {:ok, result} <- DataQuestions.catalogue(conn.assigns.tenant_context),
         do: json(conn, result)
  end

  operation(:create,
    summary: "Ask a question over the box's data",
    description:
      "The model picks typed, permission-checked read queries; it never writes SQL nor sees " <>
        "people's names. `grounded` says whether every number in the answer was found in the " <>
        "cited data. 403 data_questions_disabled, 429 ai_budget_exhausted / " <>
        "ai_daily_limit_reached, 424 llm_unavailable / llm_quota_exhausted / llm_invalid_answer.",
    parameters: [@slug],
    request_body: S.body(S.data_question_request()),
    responses: [ok: {"Answer", "application/json", S.data_question()}]
  )

  def create(conn, _params) do
    with {:ok, result} <- DataQuestions.ask(conn.assigns.tenant_context, conn.body_params),
         do: json(conn, result)
  end

  operation(:index,
    summary: "My questions, newest first; scope=all lists the box's audit log (owner, admin)",
    parameters: [
      @slug,
      %Parameter{name: :scope, in: :query, required: false, schema: %Schema{type: :string, enum: ["mine", "all"]}}
    ],
    responses: [ok: {"Questions", "application/json", S.data_questions()}]
  )

  def index(conn, params) do
    with {:ok, result} <- DataQuestions.list(conn.assigns.tenant_context, params),
         do: json(conn, result)
  end

  operation(:show,
    summary: "One question and its answer (tables are not stored)",
    parameters: [@slug, %Parameter{name: :id, in: :path, required: true, schema: S.uuid()}],
    responses: [ok: {"Question", "application/json", S.data_question()}]
  )

  def show(conn, %{id: id}) do
    with {:ok, result} <- DataQuestions.show(conn.assigns.tenant_context, id),
         do: json(conn, result)
  end
end

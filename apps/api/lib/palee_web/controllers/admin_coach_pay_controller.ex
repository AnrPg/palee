defmodule PaleeWeb.AdminCoachPayController do
  @moduledoc "Οικονομικά › Αμοιβές coaches: rules, periods, statements, export (ADR-341)."

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias OpenApiSpex.{Parameter, Schema}
  alias Palee.Application.CoachPay.CoachPayService
  alias PaleeWeb.Schemas.CoachPay, as: S

  action_fallback PaleeWeb.FallbackController

  tags(["Coach pay"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  @id %Parameter{
    name: :id,
    in: :path,
    required: true,
    schema: %Schema{type: :string, format: :uuid}
  }

  operation(:rules,
    summary: "Coach pay rules (active ones unless `include_archived`)",
    parameters: [
      %Parameter{
        name: :coach_user_id,
        in: :query,
        required: false,
        schema: %Schema{type: :string, format: :uuid}
      },
      %Parameter{
        name: :include_archived,
        in: :query,
        required: false,
        schema: %Schema{type: :boolean}
      }
    ],
    responses: [ok: {"Rules", "application/json", S.rules()}]
  )

  def rules(conn, params),
    do: json(conn, CoachPayService.rules(conn.assigns.tenant_context, params))

  operation(:create_rule,
    summary: "Add a pay rule for a coach",
    description:
      "Per class, per attendee, per personal-training session, or a percent of the sales " <>
        "attributed to the coach (`personal_training`: packages they train; `sold_by`: " <>
        "sales they recorded). The currency defaults to the business's.",
    request_body: S.body(S.rule_body([:coach_user_id, :kind, :starts_on])),
    responses: [created: {"Rule", "application/json", S.one(:rule, S.rule())}]
  )

  def create_rule(conn, _params) do
    with {:ok, rule} <- CoachPayService.create_rule(conn.assigns.tenant_context, conn.body_params) do
      conn |> put_status(:created) |> json(%{rule: rule})
    end
  end

  operation(:update_rule,
    summary: "Change a pay rule (approved periods keep what they paid)",
    parameters: [@id],
    request_body: S.body(S.rule_body([])),
    responses: [ok: {"Rule", "application/json", S.one(:rule, S.rule())}]
  )

  def update_rule(conn, %{id: id}) do
    with {:ok, rule} <-
           CoachPayService.update_rule(conn.assigns.tenant_context, id, conn.body_params) do
      json(conn, %{rule: rule})
    end
  end

  operation(:archive_rule,
    summary: "Stop a pay rule: it pays nothing after today",
    parameters: [@id],
    responses: [ok: {"Rule", "application/json", S.one(:rule, S.rule())}]
  )

  def archive_rule(conn, %{id: id}) do
    with {:ok, rule} <- CoachPayService.archive_rule(conn.assigns.tenant_context, id) do
      json(conn, %{rule: rule})
    end
  end

  operation(:periods,
    summary: "Pay periods, newest first",
    parameters: [
      %Parameter{
        name: :status,
        in: :query,
        required: false,
        schema: %Schema{type: :string, enum: ["draft", "approved", "exported"]}
      }
    ],
    responses: [ok: {"Periods", "application/json", S.periods()}]
  )

  def periods(conn, params),
    do: json(conn, CoachPayService.periods(conn.assigns.tenant_context, params))

  operation(:create_period,
    summary: "Open a pay period (gym-local dates, at most 92 days, no overlap)",
    request_body: S.body(S.period_body()),
    responses: [created: {"Period", "application/json", S.one(:period, S.period())}]
  )

  def create_period(conn, _params) do
    with {:ok, period} <-
           CoachPayService.create_period(conn.assigns.tenant_context, conn.body_params) do
      conn |> put_status(:created) |> json(%{period: Map.put(period, :statements, [])})
    end
  end

  operation(:period,
    summary: "A pay period with each coach's statement and its lines",
    parameters: [@id],
    responses: [ok: {"Period", "application/json", S.one(:period, S.period())}]
  )

  def period(conn, %{id: id}) do
    with {:ok, period} <- CoachPayService.period(conn.assigns.tenant_context, id) do
      json(conn, %{period: period})
    end
  end

  operation(:calculate,
    summary: "Calculate a draft period from the classes, sessions and sales (adjustments stay)",
    parameters: [@id],
    responses: [ok: {"Period", "application/json", S.one(:period, S.period())}]
  )

  def calculate(conn, %{id: id}) do
    with {:ok, period} <- CoachPayService.calculate(conn.assigns.tenant_context, id) do
      json(conn, %{period: period})
    end
  end

  operation(:add_adjustment,
    summary: "Add a bonus or correction to a coach's statement (draft periods only)",
    parameters: [@id],
    request_body: S.body(S.adjustment_body()),
    responses: [ok: {"Period", "application/json", S.one(:period, S.period())}]
  )

  def add_adjustment(conn, %{id: id}) do
    with {:ok, period} <-
           CoachPayService.add_adjustment(conn.assigns.tenant_context, id, conn.body_params) do
      json(conn, %{period: period})
    end
  end

  operation(:delete_adjustment,
    summary: "Remove an adjustment (draft periods only)",
    parameters: [
      @id,
      %Parameter{
        name: :line_id,
        in: :path,
        required: true,
        schema: %Schema{type: :string, format: :uuid}
      }
    ],
    responses: [ok: {"Period", "application/json", S.one(:period, S.period())}]
  )

  def delete_adjustment(conn, %{id: id, line_id: line_id}) do
    with {:ok, period} <-
           CoachPayService.delete_adjustment(conn.assigns.tenant_context, id, line_id) do
      json(conn, %{period: period})
    end
  end

  operation(:approve,
    summary: "Approve a period: its statements are locked and shown to the coaches",
    parameters: [@id],
    responses: [ok: {"Period", "application/json", S.one(:period, S.period())}]
  )

  def approve(conn, %{id: id}) do
    with {:ok, period} <- CoachPayService.approve(conn.assigns.tenant_context, id) do
      json(conn, %{period: period})
    end
  end

  operation(:reopen,
    summary: "Reopen an approved period, with a reason (an exported one stays as it is)",
    parameters: [@id],
    request_body: S.body(S.reopen_body()),
    responses: [ok: {"Period", "application/json", S.one(:period, S.period())}]
  )

  def reopen(conn, %{id: id}) do
    with {:ok, period} <-
           CoachPayService.reopen(conn.assigns.tenant_context, id, conn.body_params) do
      json(conn, %{period: period})
    end
  end

  operation(:export,
    summary: "The approved period as CSV for the accountant (marks it exported)",
    parameters: [@id],
    responses: [ok: {"CSV", "text/csv", %Schema{type: :string}}]
  )

  def export(conn, %{id: id}) do
    with {:ok, filename, csv} <- CoachPayService.export(conn.assigns.tenant_context, id) do
      conn
      |> put_resp_content_type("text/csv")
      |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
      |> send_resp(200, csv)
    end
  end
end

defmodule PaleeWeb.AdminCoachPayController do
  @moduledoc """
  Οικονομικά › Αμοιβές coaches: rules, periods, statements, export
  (ADR-341); the catalogue of overtime and allowances, lines added by hand,
  gross or net per line, the pay statement PDF, a person's statements and
  Finance's summary (ADR-382).
  """

  use PaleeWeb, :controller
  use PaleeWeb.ControllerSpecs

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

  @user_id %Parameter{
    name: :user_id,
    in: :path,
    required: true,
    schema: %Schema{type: :string, format: :uuid}
  }

  @language %Parameter{
    name: :language,
    in: :query,
    required: false,
    description: "el en de fr it nl es pt-PT ru bg (default: the business's document language)",
    schema: %Schema{type: :string}
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
      "Per class, per attendee, per personal-training session, a fixed amount per month, " <>
        "week or day (prorated by calendar days), or a percent of the sales attributed to " <>
        "the coach (`personal_training`: packages they train; `sold_by`: sales they " <>
        "recorded; `own_clients`: subscription payments of the clients they coach; " <>
        "`box_all`: every subscription payment of the box). A coach may hold any number of " <>
        "rules at once. `amount_basis` (gross by default) is inherited by the rule's lines. " <>
        "The currency defaults to the business's.",
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
    summary: "Add a line by hand to a person's statement (draft periods only)",
    description:
      "`adjustment` (default): a bonus or correction with a description; `ad_hoc` " <>
        "(«Έκτακτη πληρωμή») and `non_taxable_reimbursement` («Μη φορολογητέο»): a positive " <>
        "amount with a required note. Who added it and when stay on the line.",
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

  operation(:add_pay_item_line,
    summary: "Add an allowance from the catalogue to a person's statement (draft periods only)",
    parameters: [@id],
    request_body: S.body(S.pay_item_line_body()),
    responses: [ok: {"Period", "application/json", S.one(:period, S.period())}]
  )

  def add_pay_item_line(conn, %{id: id}) do
    with {:ok, period} <-
           CoachPayService.add_pay_item_line(conn.assigns.tenant_context, id, conn.body_params) do
      json(conn, %{period: period})
    end
  end

  operation(:set_line_basis,
    summary: "Mark a line gross or net (draft periods only)",
    description:
      "A calculated line takes its rule's basis again when the period is recalculated; a " <>
        "line added by hand keeps it.",
    parameters: [
      @id,
      %Parameter{
        name: :line_id,
        in: :path,
        required: true,
        schema: %Schema{type: :string, format: :uuid}
      }
    ],
    request_body: S.body(S.line_basis_body()),
    responses: [ok: {"Period", "application/json", S.one(:period, S.period())}]
  )

  def set_line_basis(conn, %{id: id, line_id: line_id}) do
    with {:ok, period} <-
           CoachPayService.set_line_basis(
             conn.assigns.tenant_context,
             id,
             line_id,
             conn.body_params
           ) do
      json(conn, %{period: period})
    end
  end

  operation(:delete_adjustment,
    summary: "Remove a line added by hand (draft periods only)",
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

  operation(:payslip,
    summary: "A person's pay statement of an approved period as PDF («Εκκαθαριστικό»)",
    description:
      "An internal record of the business («Εσωτερική κατάσταση αμοιβής»), not an official " <>
        "payroll document. Gross and net amounts are shown apart.",
    parameters: [@id, @user_id, @language],
    responses: [ok: {"PDF", "application/pdf", %Schema{type: :string, format: :binary}}]
  )

  def payslip(conn, %{id: id, user_id: user_id} = params) do
    with {:ok, file} <-
           CoachPayService.payslip(
             conn.assigns.tenant_context,
             id,
             user_id,
             Map.get(params, :language)
           ) do
      PaleeWeb.CoachPayFiles.send_pdf(conn, file)
    end
  end

  operation(:person_statements,
    summary: "A staff member's pay statements for their profile, with totals",
    parameters: [@user_id],
    responses: [ok: {"Statements", "application/json", S.my_statements()}]
  )

  def person_statements(conn, %{user_id: user_id}),
    do: json(conn, CoachPayService.person_statements(conn.assigns.tenant_context, user_id))

  operation(:summary,
    summary: "Finance: pay periods with each person's totals (gross and net apart)",
    parameters: [
      %Parameter{
        name: :from,
        in: :query,
        required: false,
        schema: %Schema{type: :string, format: :date}
      },
      %Parameter{
        name: :to,
        in: :query,
        required: false,
        schema: %Schema{type: :string, format: :date}
      }
    ],
    responses: [ok: {"Summary", "application/json", S.summary()}]
  )

  def summary(conn, params) do
    with {:ok, summary} <- CoachPayService.summary(conn.assigns.tenant_context, params) do
      json(conn, summary)
    end
  end

  operation(:items,
    summary: "The box's overtime and allowances (active ones unless `include_archived`)",
    parameters: [
      %Parameter{
        name: :kind,
        in: :query,
        required: false,
        schema: %Schema{type: :string, enum: ["overtime", "allowance"]}
      },
      %Parameter{
        name: :include_archived,
        in: :query,
        required: false,
        schema: %Schema{type: :boolean}
      }
    ],
    responses: [ok: {"Items", "application/json", S.items()}]
  )

  def items(conn, params),
    do: json(conn, CoachPayService.items(conn.assigns.tenant_context, params))

  operation(:create_item,
    summary: "Add overtime or an allowance to the box's catalogue",
    description:
      "Overtime: an amount per hour above `weekly_threshold` hours a week (both required), " <>
        "counted from the classes the person led. Allowance: per period or per occurrence, " <>
        "added to a period by hand. `roles`: the staff roles it applies to.",
    request_body: S.body(S.item_body([:amount_cents, :kind, :name, :roles, :unit])),
    responses: [created: {"Item", "application/json", S.one(:item, S.item())}]
  )

  def create_item(conn, _params) do
    with {:ok, item} <- CoachPayService.create_item(conn.assigns.tenant_context, conn.body_params) do
      conn |> put_status(:created) |> json(%{item: item})
    end
  end

  operation(:update_item,
    summary: "Change overtime or an allowance (statements keep the terms they paid by)",
    parameters: [@id],
    request_body: S.body(S.item_body([])),
    responses: [ok: {"Item", "application/json", S.one(:item, S.item())}]
  )

  def update_item(conn, %{id: id}) do
    with {:ok, item} <-
           CoachPayService.update_item(conn.assigns.tenant_context, id, conn.body_params) do
      json(conn, %{item: item})
    end
  end

  operation(:archive_item,
    summary: "Stop overtime or an allowance (lines already made stay)",
    parameters: [@id],
    responses: [ok: {"Item", "application/json", S.one(:item, S.item())}]
  )

  def archive_item(conn, %{id: id}) do
    with {:ok, item} <- CoachPayService.archive_item(conn.assigns.tenant_context, id) do
      json(conn, %{item: item})
    end
  end
end

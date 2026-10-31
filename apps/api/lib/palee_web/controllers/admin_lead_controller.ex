defmodule PaleeWeb.AdminLeadController do
  @moduledoc """
  ADR-344/345: the staff's «Ενδιαφερόμενοι»: the list with stages, source,
  owner and next action; one lead with its tasks and history; moving,
  notes, «Μίλησα», tasks, «Έγινε μέλος», CSV import, marketing opt-out and
  erasure.
  """

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias OpenApiSpex.{Parameter, Schema}
  alias Palee.Application.Leads.StaffLeads
  alias PaleeWeb.Growth.Params
  alias PaleeWeb.Schemas.Growth, as: G

  action_fallback PaleeWeb.FallbackController

  tags(["Admin Leads"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  @id %Parameter{name: :id, in: :path, required: true, schema: G.uuid()}
  @detail {"Lead with tasks and history", "application/json", G.lead_detail()}

  operation(:index,
    summary: "The box's leads, newest first, with the count per stage",
    parameters: [
      %Parameter{
        name: :stage,
        in: :query,
        description: "A stage, several separated by commas, or `open`",
        schema: %Schema{type: :string}
      },
      %Parameter{
        name: :owner,
        in: :query,
        description: "`me` or a staff profile id",
        schema: %Schema{type: :string}
      },
      %Parameter{name: :source, in: :query, schema: %Schema{type: :string}},
      %Parameter{
        name: :q,
        in: :query,
        description: "Name, email or phone contains",
        schema: %Schema{type: :string, maxLength: 120}
      },
      %Parameter{
        name: :limit,
        in: :query,
        schema: %Schema{type: :integer, minimum: 1, maximum: 200}
      },
      %Parameter{name: :offset, in: :query, schema: %Schema{type: :integer, minimum: 0}}
    ],
    responses: [ok: {"Leads", "application/json", G.lead_list()}]
  )

  def index(conn, params),
    do: json(conn, StaffLeads.list(context(conn), Params.stringify(params)))

  operation(:tasks,
    summary: "Open tasks of open leads, due first («Επόμενες ενέργειες»)",
    parameters: [
      %Parameter{name: :mine, in: :query, schema: %Schema{type: :boolean}},
      %Parameter{
        name: :limit,
        in: :query,
        schema: %Schema{type: :integer, minimum: 1, maximum: 200}
      }
    ],
    responses: [
      ok:
        {"Tasks", "application/json", G.one(:tasks, %Schema{type: :array, items: G.lead_task()})}
    ]
  )

  def tasks(conn, params),
    do: json(conn, %{tasks: StaffLeads.tasks(context(conn), Params.stringify(params))})

  operation(:show,
    summary: "One lead with its tasks and history",
    parameters: [@id],
    responses: [ok: @detail]
  )

  def show(conn, %{id: id}) do
    with {:ok, detail} <- StaffLeads.show(context(conn), id), do: json(conn, detail)
  end

  operation(:create,
    summary: "A lead typed in by staff (walk-in, phone call, referral, event)",
    request_body: G.body(G.lead_create_body()),
    responses: [created: @detail]
  )

  def create(conn, _params) do
    with {:ok, detail} <- StaffLeads.create(context(conn), body(conn)) do
      conn |> put_status(:created) |> json(detail)
    end
  end

  operation(:update,
    summary: "Change a lead's details or owner",
    parameters: [@id],
    request_body: G.body(G.lead_update_body()),
    responses: [ok: @detail]
  )

  def update(conn, %{id: id}),
    do: reply(conn, StaffLeads.update(context(conn), id, body(conn)))

  operation(:move,
    summary: "Move a lead to another stage (`lost` with a reason)",
    parameters: [@id],
    request_body: G.body(G.lead_move_body()),
    responses: [ok: @detail]
  )

  def move(conn, %{id: id}), do: reply(conn, StaffLeads.move(context(conn), id, body(conn)))

  operation(:note,
    summary: "A note in the lead's history",
    parameters: [@id],
    request_body: G.body(G.lead_note_body()),
    responses: [ok: @detail]
  )

  def note(conn, %{id: id}), do: reply(conn, StaffLeads.note(context(conn), id, body(conn)))

  operation(:contacted,
    summary: "«Μίλησα»: staff reached the person",
    parameters: [@id],
    request_body: G.body(G.lead_contacted_body()),
    responses: [ok: @detail]
  )

  def contacted(conn, %{id: id}),
    do: reply(conn, StaffLeads.contacted(context(conn), id, body(conn)))

  operation(:add_task,
    summary: "A task on the lead («Επόμενη ενέργεια»)",
    parameters: [@id],
    request_body: G.body(G.lead_task_body()),
    responses: [ok: @detail]
  )

  def add_task(conn, %{id: id}),
    do: reply(conn, StaffLeads.add_task(context(conn), id, body(conn)))

  operation(:complete_task,
    summary: "Mark a lead's task done",
    parameters: [%Parameter{name: :task_id, in: :path, required: true, schema: G.uuid()}],
    responses: [ok: @detail]
  )

  def complete_task(conn, %{task_id: task_id}),
    do: reply(conn, StaffLeads.complete_task(context(conn), task_id))

  operation(:convert,
    summary: "«Έγινε μέλος»: link the lead to a box member and close it, keeping its history",
    parameters: [@id],
    request_body: G.body(G.lead_convert_body()),
    responses: [ok: @detail]
  )

  def convert(conn, %{id: id}),
    do: reply(conn, StaffLeads.convert(context(conn), id, body(conn)))

  operation(:opt_out,
    summary: "The person asked for no marketing messages",
    parameters: [@id],
    responses: [ok: @detail]
  )

  def opt_out(conn, %{id: id}), do: reply(conn, StaffLeads.opt_out(context(conn), id))

  operation(:import,
    summary: "Leads from a CSV file (`dry_run` reports per row without writing)",
    request_body: G.body(G.lead_import_body()),
    responses: [ok: {"Import result", "application/json", G.lead_import_result()}]
  )

  def import(conn, _params) do
    with {:ok, result} <- StaffLeads.import_csv(context(conn), body(conn)), do: json(conn, result)
  end

  operation(:delete,
    summary: "Erase a lead with its tasks and history (an erasure request)",
    parameters: [@id],
    responses: [no_content: "Erased"]
  )

  def delete(conn, %{id: id}) do
    with :ok <- StaffLeads.erase(context(conn), id), do: send_resp(conn, :no_content, "")
  end

  defp reply(conn, {:ok, detail}), do: json(conn, detail)
  defp reply(_conn, error), do: error

  defp context(conn), do: conn.assigns.tenant_context
  defp body(conn), do: Params.stringify(conn.body_params)
end

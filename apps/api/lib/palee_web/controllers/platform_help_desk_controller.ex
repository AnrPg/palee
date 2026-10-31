defmodule PaleeWeb.PlatformHelpDeskController do
  @moduledoc """
  ADR-363, vendor console › «Υποστήριξη»: the Palee team's queue of
  tickets handed over by boxes' staff, each with its conversation, a reply
  and its state. Reading or answering a ticket is in the vendors' audit log.
  """

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias OpenApiSpex.{Parameter, Schema}
  alias Palee.Application.HelpDesk.PlatformHelpDesk
  alias PaleeWeb.Schemas.AiHelp, as: S

  action_fallback PaleeWeb.FallbackController

  tags(["Platform help desk"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  @id %Parameter{name: :id, in: :path, required: true, schema: S.uuid()}

  operation(:index,
    summary: "Tickets of every box, urgent first then oldest (vendors)",
    parameters: [
      %Parameter{
        name: :status,
        in: :query,
        required: false,
        schema: %Schema{type: :string, enum: Palee.HelpDesk.ticket_statuses()}
      }
    ],
    responses: [ok: {"Tickets", "application/json", S.tickets()}]
  )

  def index(conn, params) do
    with {:ok, result} <- PlatformHelpDesk.tickets(conn.assigns.platform_context, params),
         do: json(conn, result)
  end

  operation(:show,
    summary: "One ticket with its conversation (audited)",
    parameters: [@id],
    responses: [ok: {"Ticket", "application/json", S.ticket_detail()}]
  )

  def show(conn, %{id: id}) do
    with {:ok, result} <- PlatformHelpDesk.show(conn.assigns.platform_context, id),
         do: json(conn, result)
  end

  operation(:reply,
    summary: "Answer the box (the ticket waits on the box, or is solved)",
    parameters: [@id],
    request_body: S.body(S.reply_request()),
    responses: [ok: {"Ticket", "application/json", S.ticket_detail()}]
  )

  def reply(conn, %{id: id}) do
    with {:ok, result} <-
           PlatformHelpDesk.reply(conn.assigns.platform_context, id, conn.body_params),
         do: json(conn, result)
  end

  operation(:update,
    summary: "Change a ticket's state, priority or assignee",
    parameters: [@id],
    request_body: S.body(S.ticket_update_request()),
    responses: [ok: {"Ticket", "application/json", S.ticket_detail()}]
  )

  def update(conn, %{id: id}) do
    with {:ok, result} <-
           PlatformHelpDesk.update(conn.assigns.platform_context, id, conn.body_params),
         do: json(conn, result)
  end
end

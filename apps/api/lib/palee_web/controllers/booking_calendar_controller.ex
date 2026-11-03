defmodule PaleeWeb.BookingCalendarController do
  @moduledoc "ADR-359 (CP-E4): one booking as an .ics invite, same UID as the calendar feed."

  use PaleeWeb, :controller
  use PaleeWeb.ControllerSpecs

  alias Palee.Application.BookingCalendarInvite
  alias PaleeWeb.Schemas.TrainingFloor, as: S
  alias OpenApiSpex.Schema

  action_fallback PaleeWeb.FallbackController

  tags(["Calendar"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  operation(:show,
    summary: "Your booking as an iCalendar invite (METHOD:CANCEL once it is cancelled)",
    parameters: [
      id: [in: :path, required: true, schema: %Schema{type: :string, format: :uuid}]
    ],
    responses: [
      ok: {"iCalendar invite", "text/calendar", %Schema{type: :string}},
      not_found: {"No such booking of yours", "application/json", S.error()}
    ]
  )

  def show(conn, %{id: id}) do
    with {:ok, invite} <- BookingCalendarInvite.call(conn.assigns.tenant_context, id) do
      conn
      |> put_resp_content_type("text/calendar")
      |> put_resp_header("content-disposition", ~s(attachment; filename="#{invite.filename}"))
      |> send_resp(200, invite.ics)
    end
  end
end

defmodule PaleeWeb.MemberActivityController do
  @moduledoc """
  ADR-760 (ANR 5A): the changes the box shared with the member («Να το δει
  και το μέλος»), newest first, without who on the staff made them.
  """

  use PaleeWeb, :controller
  use PaleeWeb.ControllerSpecs

  alias OpenApiSpex.{Parameter, Schema}
  alias Palee.ActivityLog
  alias PaleeWeb.Schemas.ActivityLog, as: S

  action_fallback PaleeWeb.FallbackController

  tags(["Activity log"])
  security([%{"bearerAuth" => []}])

  operation(:index,
    summary: "What the box shared with me about changes to my membership",
    parameters: [%Parameter{name: :cursor, in: :query, schema: %Schema{type: :string}}],
    responses: [ok: {"Shared changes", "application/json", S.member_page()}]
  )

  def index(conn, params) do
    with {:ok, page} <- ActivityLog.list_for_member(conn.assigns.tenant_context, params),
         do: json(conn, page)
  end
end

defmodule PaleeWeb.AdminJoinRequestController do
  @moduledoc "ADR-552: the staff answer «Ζήτα να γίνεις μέλος» (Μέλη › Θέλουν να γίνουν μέλη)."

  use PaleeWeb, :controller
  use PaleeWeb.ControllerSpecs

  alias Palee.Application.JoinBox
  alias PaleeWeb.Schemas.JoinRequests, as: S
  alias OpenApiSpex.{Parameter, Schema}

  action_fallback PaleeWeb.FallbackController

  tags(["Join requests"])
  security([%{"bearerAuth" => []}])

  @id %Parameter{
    name: :id,
    in: :path,
    required: true,
    schema: %Schema{type: :string, format: :uuid}
  }
  @refused [
    not_found: {"No such request", "application/json", %Schema{type: :object}},
    conflict: {"Already answered", "application/json", %Schema{type: :object}}
  ]

  operation(:index,
    summary: "Open requests to join the box, oldest first",
    responses: [ok: {"Requests", "application/json", S.staff_list()}]
  )

  def index(conn, _params),
    do: json(conn, %{requests: JoinBox.list(conn.assigns.tenant_context)})

  operation(:accept,
    summary: "Accept a request: the person becomes a box member",
    parameters: [@id],
    responses: [ok: {"Request", "application/json", S.staff_response()}] ++ @refused
  )

  def accept(conn, %{"id" => id}), do: decide(conn, id, "accept")

  operation(:decline,
    summary: "Decline a request",
    parameters: [@id],
    responses: [ok: {"Request", "application/json", S.staff_response()}] ++ @refused
  )

  def decline(conn, %{"id" => id}), do: decide(conn, id, "decline")

  defp decide(conn, id, action) do
    with {:ok, request} <- JoinBox.decide(conn.assigns.tenant_context, id, action),
         do: json(conn, %{request: request})
  end
end

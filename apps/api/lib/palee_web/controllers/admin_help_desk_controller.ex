defmodule PaleeWeb.AdminHelpDeskController do
  @moduledoc """
  ADR-363 (CP-G3): a staff person's support conversations with Palee. The
  AI first line answers from help-centre articles only, citing them; the
  person can hand the conversation to the Palee team at any time.
  """

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias OpenApiSpex.{Parameter, Schema}
  alias Palee.Application.HelpDesk.HelpDesk
  alias PaleeWeb.Schemas.AiHelp, as: S

  action_fallback PaleeWeb.FallbackController

  tags(["Help desk"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  @slug %Parameter{
    name: :organization_slug,
    in: :path,
    required: false,
    schema: %Schema{type: :string}
  }
  @id %Parameter{name: :id, in: :path, required: true, schema: S.uuid()}

  operation(:index,
    summary: "My support conversations, latest first",
    parameters: [@slug],
    responses: [ok: {"Conversations", "application/json", S.conversations()}]
  )

  def index(conn, _params) do
    with {:ok, result} <- HelpDesk.list(conn.assigns.tenant_context), do: json(conn, result)
  end

  operation(:create,
    summary: "Start a support conversation; the assistant answers from the help centre",
    parameters: [@slug],
    request_body: S.body(S.start_request()),
    responses: [ok: {"Conversation", "application/json", S.conversation()}]
  )

  def create(conn, _params) do
    with {:ok, result} <- HelpDesk.start(conn.assigns.tenant_context, conn.body_params),
         do: json(conn, result)
  end

  operation(:show,
    summary: "One of my conversations with its messages",
    parameters: [@slug, @id],
    responses: [ok: {"Conversation", "application/json", S.conversation()}]
  )

  def show(conn, %{id: id}) do
    with {:ok, result} <- HelpDesk.show(conn.assigns.tenant_context, id), do: json(conn, result)
  end

  operation(:message,
    summary: "Write in a conversation (the assistant answers while it has it)",
    parameters: [@slug, @id],
    request_body: S.body(S.message_request()),
    responses: [ok: {"Conversation", "application/json", S.conversation()}]
  )

  def message(conn, %{id: id}) do
    with {:ok, result} <-
           HelpDesk.post_message(conn.assigns.tenant_context, id, conn.body_params),
         do: json(conn, result)
  end

  operation(:hand_off,
    summary: "Hand the conversation to the Palee team (opens a ticket; idempotent)",
    parameters: [@slug, @id],
    request_body: S.body(S.hand_off_request()),
    responses: [ok: {"Conversation", "application/json", S.conversation()}]
  )

  def hand_off(conn, %{id: id}) do
    with {:ok, result} <- HelpDesk.hand_off(conn.assigns.tenant_context, id, conn.body_params),
         do: json(conn, result)
  end

  operation(:resolve,
    summary: "Close the conversation (and its ticket)",
    parameters: [@slug, @id],
    responses: [ok: {"Conversation", "application/json", S.conversation()}]
  )

  def resolve(conn, %{id: id}) do
    with {:ok, result} <- HelpDesk.resolve(conn.assigns.tenant_context, id),
         do: json(conn, result)
  end
end

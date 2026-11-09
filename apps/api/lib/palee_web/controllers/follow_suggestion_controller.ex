defmodule PaleeWeb.FollowSuggestionController do
  @moduledoc "«Ίσως γνωρίζεις» (ADR-561): people to follow, follow from a suggestion, ✕ and undo."

  use PaleeWeb, :controller
  use PaleeWeb.ControllerSpecs

  alias Palee.Application.FollowSuggestions
  alias PaleeWeb.Schemas.Social, as: S
  alias OpenApiSpex.{Parameter, Schema}

  action_fallback PaleeWeb.FallbackController

  tags(["Follows"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  @id %Parameter{name: :id, in: :path, required: true, schema: S.uuid()}
  @no_content [no_content: {"Done", "application/json", %Schema{type: :object}}]

  operation(:index,
    summary:
      "ADR-561: people to follow, ranked, each with one reason; broad for new people, personal as their network grows",
    parameters: [
      %Parameter{
        name: :limit,
        in: :query,
        required: false,
        schema: %Schema{type: :integer, minimum: 1, maximum: FollowSuggestions.max_limit()}
      },
      %Parameter{
        name: :seed,
        in: :query,
        required: false,
        description:
          "«Και αυτοί ίσως»: also the people this person follows, when you may see them",
        schema: S.uuid()
      }
    ],
    responses: [ok: {"Suggestions", "application/json", S.follow_suggestions_response()}]
  )

  def index(conn, params) do
    with {:ok, result} <- FollowSuggestions.list(conn.assigns.user_context, params),
         do: json(conn, result)
  end

  operation(:follow,
    summary: "Follow a suggested person (a request when private), counted for the reason shown",
    parameters: [@id],
    request_body: S.body(S.follow_suggestion_action()),
    responses: [ok: {"Status", "application/json", S.follow_status_response()}]
  )

  def follow(conn, %{id: id}) do
    with {:ok, status} <-
           FollowSuggestions.follow(conn.assigns.user_context, id, conn.body_params.reason),
         do: json(conn, status)
  end

  operation(:dismiss,
    summary: "✕: stop suggesting this person, unless they start following you",
    parameters: [@id],
    request_body: S.body(S.follow_suggestion_action()),
    responses: @no_content
  )

  def dismiss(conn, %{id: id}) do
    with :ok <- FollowSuggestions.dismiss(conn.assigns.user_context, id, conn.body_params.reason),
         do: send_resp(conn, :no_content, "")
  end

  operation(:undismiss,
    summary: "Undo ✕",
    parameters: [@id],
    responses: @no_content
  )

  def undismiss(conn, %{id: id}) do
    with :ok <- FollowSuggestions.undismiss(conn.assigns.user_context, id),
         do: send_resp(conn, :no_content, "")
  end
end

defmodule PaleeWeb.AdminFollowerInviteController do
  @moduledoc "ADR-580: Χρήστες › «Ακόλουθοι, όχι μέλη»: the box invites its followers to become box members."

  use PaleeWeb, :controller
  use PaleeWeb.ControllerSpecs

  alias Palee.Application.FollowerInvites
  alias PaleeWeb.Schemas.FollowerInvites, as: S
  alias OpenApiSpex.{Parameter, Schema}

  action_fallback PaleeWeb.FallbackController

  tags(["Follower invites"])
  security([%{"bearerAuth" => []}])

  operation(:summary,
    summary: "How many followers are not box members, and how many may be invited now",
    responses: [ok: {"Counts", "application/json", S.summary_response()}]
  )

  def summary(conn, _params) do
    with {:ok, counts} <- FollowerInvites.summary(conn.assigns.tenant_context),
         do: json(conn, %{counts: counts})
  end

  operation(:index,
    summary: "Followers who are not box members, newest follow first",
    parameters: [
      %Parameter{
        name: :filter,
        in: :query,
        required: false,
        schema: %Schema{type: :string, enum: ~w(all trial former)}
      },
      %Parameter{name: :cursor, in: :query, required: false, schema: %Schema{type: :string}}
    ],
    responses: [
      ok: {"Followers", "application/json", S.list_response()},
      unprocessable_entity: {"Bad filter or cursor", "application/json", %Schema{type: :object}}
    ]
  )

  def index(conn, params) do
    with {:ok, page} <- FollowerInvites.list(conn.assigns.tenant_context, params),
         do: json(conn, page)
  end

  operation(:create,
    summary: "Invite followers to become box members",
    description:
      "Each one gets a notification and a message from the box. People who declined or were invited in the last 90 days come back in skipped.",
    request_body: {"Invitation", "application/json", S.send_request()},
    responses: [
      created: {"Sent", "application/json", S.send_response()},
      unprocessable_entity: {"Invalid invitation", "application/json", %Schema{type: :object}}
    ]
  )

  def create(conn, _params) do
    with {:ok, result} <- FollowerInvites.send(conn.assigns.tenant_context, conn.body_params) do
      conn |> put_status(:created) |> json(result)
    end
  end
end

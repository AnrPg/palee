defmodule PaleeWeb.FollowerInviteController do
  @moduledoc "ADR-580: a person's invitation from a box they follow to become a box member."

  use PaleeWeb, :controller
  use PaleeWeb.ControllerSpecs

  alias Palee.Application.FollowerInvites
  alias PaleeWeb.Schemas.FollowerInvites, as: S
  alias OpenApiSpex.{Parameter, Schema}

  action_fallback PaleeWeb.FallbackController

  tags(["Follower invites"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  @slug %Parameter{
    name: :slug,
    in: :path,
    required: true,
    description: "The box's slug or one of its former slugs",
    schema: %Schema{type: :string, maxLength: 120}
  }

  operation(:show,
    summary: "Your open invitation from a published box to become a box member, or null",
    parameters: [@slug],
    responses: [
      ok: {"Invitation", "application/json", S.mine_response()},
      not_found: {"No such box", "application/json", %Schema{type: :object}}
    ]
  )

  def show(conn, %{slug: slug}) do
    with {:ok, invite} <- FollowerInvites.mine(account(conn), slug),
         do: json(conn, %{invite: invite})
  end

  operation(:decline,
    summary: "«Όχι, ευχαριστώ»: no more invitations from this box",
    parameters: [@slug],
    responses: [
      ok: {"Invitation", "application/json", S.mine_response()},
      not_found: {"No such box or invitation", "application/json", %Schema{type: :object}}
    ]
  )

  def decline(conn, %{slug: slug}) do
    with {:ok, _invite} <- FollowerInvites.decline(account(conn), slug),
         do: json(conn, %{invite: nil})
  end

  defp account(conn), do: conn.assigns.user_context.account
end

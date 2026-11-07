defmodule PaleeWeb.JoinRequestController do
  @moduledoc "ADR-552: a person's «Ζήτα να γίνεις μέλος» at a box."

  use PaleeWeb, :controller
  use PaleeWeb.ControllerSpecs

  alias Palee.Application.JoinBox
  alias PaleeWeb.Schemas.JoinRequests, as: S
  alias OpenApiSpex.{Parameter, Schema}

  action_fallback PaleeWeb.FallbackController

  tags(["Join requests"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  @slug %Parameter{
    name: :slug,
    in: :path,
    required: true,
    description: "The box's slug or one of its former slugs",
    schema: %Schema{type: :string, maxLength: 120}
  }
  @refused [
    not_found: {"No such box or request", "application/json", %Schema{type: :object}},
    conflict: {"Already a box member", "application/json", %Schema{type: :object}}
  ]

  operation(:show,
    summary: "Your latest request to join a published box, or null",
    parameters: [@slug],
    responses: [ok: {"Request", "application/json", S.mine_response()}] ++ @refused
  )

  def show(conn, %{slug: slug}) do
    with {:ok, request} <- JoinBox.mine(account(conn), slug), do: json(conn, %{request: request})
  end

  operation(:create,
    summary: "Ask a published box to take you in as a box member",
    description: "Asking again while a request is open returns it.",
    parameters: [@slug],
    responses: [created: {"Request", "application/json", S.mine_response()}] ++ @refused
  )

  def create(conn, %{slug: slug}) do
    with {:ok, request} <- JoinBox.ask(account(conn), slug) do
      conn |> put_status(:created) |> json(%{request: request})
    end
  end

  operation(:cancel,
    summary: "Withdraw your open request to join",
    parameters: [@slug],
    responses: [ok: {"Request", "application/json", S.mine_response()}] ++ @refused
  )

  def cancel(conn, %{slug: slug}) do
    with {:ok, request} <- JoinBox.cancel(account(conn), slug),
         do: json(conn, %{request: request})
  end

  defp account(conn), do: conn.assigns.user_context.account
end

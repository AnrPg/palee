defmodule PaleeWeb.PublicSmsUnsubscribeController do
  @moduledoc """
  ADR-390: the short link at the end of a marketing SMS, read by the public
  page `/u/:token`. No sign-in; the token is signed and names the contact.

    * `GET /api/public/channels/unsubscribe/:token` – the box's name and
      whether offers by SMS are already off. Changes nothing, so a link
      preview unsubscribes nobody.
    * `POST …/:token` – withdraws the person's marketing SMS consent at that
      box (source `unsubscribe_link`). Tapping again changes nothing.
  """

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias OpenApiSpex.{Parameter, Schema}
  alias Palee.Application.Channels.SmsUnsubscribe
  alias PaleeWeb.Schemas.Channels, as: S

  action_fallback PaleeWeb.FallbackController

  tags(["Channels"])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  @token %Parameter{
    name: :token,
    in: :path,
    required: true,
    schema: %Schema{type: :string, maxLength: 64}
  }

  operation(:show,
    summary: "The box behind a marketing SMS's unsubscribe link (changes nothing)",
    security: [],
    parameters: [@token],
    responses: [
      ok: {"Unsubscribe link", "application/json", S.unsubscribe()},
      not_found: {"Unknown link", "application/json", %Schema{type: :object}}
    ]
  )

  def show(conn, %{token: token}) do
    with {:ok, view} <- SmsUnsubscribe.show(token) do
      conn |> put_resp_header("cache-control", "private, no-store") |> json(view)
    end
  end

  operation(:create,
    summary: "Stop offers by SMS from this box (withdraws the marketing SMS consent)",
    security: [],
    parameters: [@token],
    responses: [
      ok: {"Unsubscribed", "application/json", S.unsubscribe()},
      not_found: {"Unknown link", "application/json", %Schema{type: :object}}
    ]
  )

  def create(conn, %{token: token}) do
    with {:ok, view} <- SmsUnsubscribe.withdraw(token) do
      conn |> put_resp_header("cache-control", "private, no-store") |> json(view)
    end
  end
end

defmodule PaleeWeb.EmailListHookController do
  @moduledoc """
  Mailchimp's and Brevo's unsubscribe webhook (ADR-380, 2026-11-03): no
  session, the connection's secret token in the address. Someone who
  unsubscribes on the provider's side has their marketing-email switch in
  Palee turned off. Mailchimp checks the address with a `GET` first.
  """

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias OpenApiSpex.{MediaType, Parameter, RequestBody, Schema}
  alias Palee.Application.Integrations.MarketingConsents
  alias PaleeWeb.Schemas.OpenPlatform, as: S

  action_fallback PaleeWeb.FallbackController

  tags(["Integrations"])

  operation(:unsubscribe,
    summary: "The email list's unsubscribe webhook (Mailchimp or Brevo); GET checks the address",
    description:
      "The address with its token is made in Settings › Connections › Email list. An unknown " <>
        "connection and a wrong token answer the same 404. Mailchimp posts a form " <>
        "(`type=unsubscribe`), Brevo posts JSON (`event: unsubscribed`); other events are ignored.",
    security: [],
    parameters: [
      %Parameter{name: :id, in: :path, required: true, schema: S.uuid()},
      %Parameter{
        name: :token,
        in: :query,
        required: true,
        schema: %Schema{type: :string, maxLength: 200}
      }
    ],
    request_body: %RequestBody{
      required: false,
      content: %{
        "application/json" => %MediaType{
          schema: %Schema{type: :object, additionalProperties: true}
        },
        "application/x-www-form-urlencoded" => %MediaType{
          schema: %Schema{type: :object, additionalProperties: true}
        }
      }
    },
    responses: [ok: {"Handled", "application/json", S.withdrawn()}]
  )

  def unsubscribe(conn, %{"id" => id} = params) do
    fields = if conn.method == "GET", do: %{}, else: conn.body_params

    with {:ok, result} <- MarketingConsents.provider_unsubscribe(id, params["token"], fields),
         do: json(conn, result)
  end
end

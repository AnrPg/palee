defmodule PaleeWeb.MarketingConsentController do
  @moduledoc """
  Profile › «Ενημερώσεις με email» (ADR-380): the member's own yes or no to
  the box's marketing email. Off by default; only the member sets it.
  """

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Palee.Application.Integrations.MarketingConsents
  alias PaleeWeb.Schemas.OpenPlatform, as: S

  action_fallback PaleeWeb.FallbackController

  tags(["Integrations"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  operation(:show,
    summary: "Whether I agreed to the box's marketing email",
    responses: [ok: {"Consent", "application/json", S.consent()}]
  )

  def show(conn, _params), do: json(conn, MarketingConsents.show(conn.assigns.tenant_context))

  operation(:update,
    summary: "Say yes or no to the box's marketing email",
    description:
      "Yes adds me to the box's email list (Mailchimp or Brevo) at the next sync with my " <>
        "email and first name only; no unsubscribes me there.",
    request_body: S.body(S.consent_body()),
    responses: [ok: {"Consent", "application/json", S.consent()}]
  )

  def update(conn, _params) do
    with {:ok, consent} <-
           MarketingConsents.update(conn.assigns.tenant_context, conn.body_params),
         do: json(conn, consent)
  end
end

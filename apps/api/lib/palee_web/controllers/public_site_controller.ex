defmodule PaleeWeb.PublicSiteController do
  @moduledoc """
  The box's website without an account (ADR-352..354): the site, the host
  lookup behind custom domains, Caddy's on-demand TLS check, the forms and
  the consent log.
  """

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Palee.Application.BoxSite.PublicSite
  alias PaleeWeb.Schemas.BoxSite, as: S
  alias OpenApiSpex.{Parameter, Schema}

  action_fallback PaleeWeb.FallbackController

  tags(["Box website"])

  plug OpenApiSpex.Plug.CastAndValidate,
       [json_render_error_v2: true] when action in [:submit_form, :consent]

  @slug %Parameter{
    name: :slug,
    in: :path,
    required: true,
    description: "The box's slug or one of its former slugs",
    schema: %Schema{type: :string, maxLength: 120}
  }
  @not_found {"No published box", "application/json", %Schema{type: :object}}
  @error {"Error", "application/json", %Schema{type: :object}}

  operation(:show,
    summary: "A published box's website: sections, FAQ, forms, tags and timetable",
    parameters: [@slug],
    responses: [ok: {"Site", "application/json", S.public_site()}, not_found: @not_found]
  )

  def show(conn, %{"slug" => slug}) do
    with {:ok, site} <- PublicSite.show(slug), do: json(conn, site)
  end

  operation(:by_host,
    summary: "The box behind a custom domain (the web's host rewrite and the TLS probe)",
    parameters: [
      %Parameter{name: :host, in: :path, required: true, schema: %Schema{type: :string, maxLength: 253}}
    ],
    responses: [ok: {"Site", "application/json", S.by_host_response()}, not_found: @not_found]
  )

  def by_host(conn, %{"host" => host}) do
    with {:ok, site} <- PublicSite.by_host(host), do: json(conn, site)
  end

  operation(:tls_allowed,
    summary: "On-demand TLS `ask`: 200 only for a verified custom domain",
    parameters: [
      %Parameter{name: :domain, in: :query, required: true, schema: %Schema{type: :string, maxLength: 253}}
    ],
    responses: [ok: {"Allowed", "application/json", %Schema{type: :object}}, not_found: @not_found]
  )

  def tls_allowed(conn, params) do
    with :ok <- PublicSite.tls_allowed(params["domain"]), do: json(conn, %{allowed: true})
  end

  operation(:submit_form,
    summary: "Send the trial or contact form; it reaches the box as a lead",
    parameters: [
      @slug,
      %Parameter{
        name: :kind,
        in: :path,
        required: true,
        schema: %Schema{type: :string, enum: ["trial", "contact"]}
      }
    ],
    request_body: S.body(S.form_request()),
    responses: [
      accepted: {"Received", "application/json", S.form_response()},
      not_found: @not_found,
      conflict: @error,
      unprocessable_entity: @error
    ]
  )

  def submit_form(conn, %{slug: slug, kind: kind}) do
    with {:ok, :received} <- PublicSite.submit_form(slug, kind, conn.body_params) do
      conn |> put_status(:accepted) |> json(%{status: "received"})
    end
  end

  operation(:consent,
    summary: "Record a visitor's cookie choice; answers which tags may load",
    parameters: [@slug],
    request_body: S.body(S.consent_request()),
    responses: [
      created: {"Recorded", "application/json", S.consent_response()},
      not_found: @not_found,
      unprocessable_entity: @error
    ]
  )

  def consent(conn, %{slug: slug}) do
    with {:ok, consent} <- PublicSite.record_consent(slug, conn.body_params) do
      conn |> put_status(:created) |> json(consent)
    end
  end
end

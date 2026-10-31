defmodule PaleeWeb.AdminSiteController do
  @moduledoc "Staff set up the box's website and its custom domains (ADR-352..354)."

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Palee.Application.BoxSite.SiteAdmin
  alias PaleeWeb.Schemas.BoxSite, as: S
  alias OpenApiSpex.{Parameter, Schema}

  action_fallback PaleeWeb.FallbackController

  tags(["Box website"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate,
       [json_render_error_v2: true] when action in [:update, :add_domain]

  @id %Parameter{name: :id, in: :path, required: true, schema: %Schema{type: :string, format: :uuid}}
  @error {"Error", "application/json", %Schema{type: :object}}

  operation(:show,
    summary: "The website's settings, section keys and custom domains",
    responses: [ok: {"Site", "application/json", S.admin_site_response()}]
  )

  def show(conn, _params) do
    with {:ok, site} <- SiteAdmin.show(conn.assigns.tenant_context), do: json(conn, site)
  end

  operation(:update,
    summary: "Change the website's sections, FAQ, forms and tags; live at once",
    request_body: S.body(S.settings_update()),
    responses: [
      ok: {"Settings", "application/json", S.settings_response()},
      conflict: {"Saved meanwhile", "application/json", %Schema{type: :object}},
      unprocessable_entity: @error
    ]
  )

  def update(conn, _params) do
    with {:ok, settings} <- SiteAdmin.update(conn.assigns.tenant_context, conn.body_params),
         do: json(conn, settings)
  end

  operation(:summary,
    summary: "What the website brought in over the last 30 days (counts only)",
    responses: [ok: {"Summary", "application/json", S.summary_response()}]
  )

  def summary(conn, _params) do
    with {:ok, summary} <- SiteAdmin.summary(conn.assigns.tenant_context), do: json(conn, summary)
  end

  operation(:domains,
    summary: "The website's custom domains with the DNS records to add",
    responses: [ok: {"Domains", "application/json", S.domains_response()}]
  )

  def domains(conn, _params) do
    json(conn, %{domains: SiteAdmin.domains(conn.assigns.tenant_context)})
  end

  operation(:add_domain,
    summary: "Add a custom domain (up to 2); it is checked at once",
    request_body: S.body(S.domain_request()),
    responses: [
      created: {"Domain", "application/json", S.domain_response()},
      conflict: @error,
      unprocessable_entity: @error
    ]
  )

  def add_domain(conn, _params) do
    params = Map.new(conn.body_params, fn {key, value} -> {to_string(key), value} end)

    with {:ok, domain} <- SiteAdmin.add_domain(conn.assigns.tenant_context, params) do
      conn |> put_status(:created) |> json(%{domain: domain})
    end
  end

  operation(:check_domain,
    summary: "«Έλεγχος τώρα»: check a custom domain's DNS and HTTPS now",
    parameters: [@id],
    responses: [ok: {"Domain", "application/json", S.domain_response()}, not_found: @error]
  )

  def check_domain(conn, %{"id" => id}) do
    with {:ok, domain} <- SiteAdmin.check_domain(conn.assigns.tenant_context, id),
         do: json(conn, %{domain: domain})
  end

  operation(:make_primary,
    summary: "Make a custom domain the site's main address",
    parameters: [@id],
    responses: [ok: {"Domain", "application/json", S.domain_response()}, not_found: @error]
  )

  def make_primary(conn, %{"id" => id}) do
    with {:ok, domain} <- SiteAdmin.make_primary(conn.assigns.tenant_context, id),
         do: json(conn, %{domain: domain})
  end

  operation(:remove_domain,
    summary: "Remove a custom domain; the site stays at its Palee address",
    parameters: [@id],
    responses: [no_content: {"Removed", "application/json", %Schema{type: :object}}, not_found: @error]
  )

  def remove_domain(conn, %{"id" => id}) do
    with :ok <- SiteAdmin.remove_domain(conn.assigns.tenant_context, id),
         do: send_resp(conn, :no_content, "")
  end
end

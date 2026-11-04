defmodule PaleeWeb.AdminSiteController do
  @moduledoc "Staff set up the box's website and its custom domains (ADR-352..354)."

  use PaleeWeb, :controller
  use PaleeWeb.ControllerSpecs

  alias Palee.Application.BoxSite.{SiteAdmin, SiteTranslations}
  alias PaleeWeb.Schemas.BoxSite, as: S
  alias OpenApiSpex.{Parameter, Schema}

  action_fallback PaleeWeb.FallbackController

  tags(["Box website"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate,
       [json_render_error_v2: true]
       when action in [
              :update,
              :add_domain,
              :save_translations,
              :keep_translations,
              :machine_translations
            ]

  @id %Parameter{
    name: :id,
    in: :path,
    required: true,
    schema: %Schema{type: :string, format: :uuid}
  }
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

  # ── Draft and publish (ADR-530) ─────────────────────────────────────────

  operation(:publish,
    summary: "«Δημοσίευση»: the draft (look and section switches) goes live",
    responses: [
      ok: {"Settings", "application/json", S.settings_only_response()},
      conflict: {"Saved meanwhile", "application/json", %Schema{type: :object}}
    ]
  )

  def publish(conn, _params) do
    with {:ok, answer} <- SiteAdmin.publish(conn.assigns.tenant_context), do: json(conn, answer)
  end

  operation(:discard_draft,
    summary: "«Απόρριψη αλλαγών»: throw the draft away; the live site stays as it is",
    responses: [
      ok: {"Settings", "application/json", S.settings_only_response()},
      conflict: {"Saved meanwhile", "application/json", %Schema{type: :object}}
    ]
  )

  def discard_draft(conn, _params) do
    with {:ok, answer} <- SiteAdmin.discard_draft(conn.assigns.tenant_context),
         do: json(conn, answer)
  end

  operation(:dismiss_notice,
    summary: "Hide the notice that the site moved to the «Αρένα» template",
    responses: [
      ok: {"Settings", "application/json", S.settings_only_response()},
      conflict: {"Saved meanwhile", "application/json", %Schema{type: :object}}
    ]
  )

  def dismiss_notice(conn, _params) do
    with {:ok, answer} <- SiteAdmin.dismiss_notice(conn.assigns.tenant_context),
         do: json(conn, answer)
  end

  operation(:preview,
    summary: "The website as it will look once the draft is published (public-site shape)",
    parameters: [
      %Parameter{
        name: :lang,
        in: :query,
        required: false,
        description:
          "One of the site's translations (ADR-520); the box's own language when absent",
        schema: S.translation_locale()
      }
    ],
    responses: [ok: {"Site", "application/json", S.public_site()}, not_found: @error]
  )

  def preview(conn, params) do
    language = if is_binary(params["lang"]), do: params["lang"]

    with {:ok, site} <- SiteAdmin.preview(conn.assigns.tenant_context, language),
         do: json(conn, site)
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
    responses: [
      no_content: {"Removed", "application/json", %Schema{type: :object}},
      not_found: @error
    ]
  )

  def remove_domain(conn, %{"id" => id}) do
    with :ok <- SiteAdmin.remove_domain(conn.assigns.tenant_context, id),
         do: send_resp(conn, :no_content, "")
  end

  operation(:send_instructions,
    summary: "«Στείλε τις οδηγίες»: email the domain's DNS records with a status link",
    parameters: [@id],
    request_body: S.body(PaleeWeb.Schemas.BoxReviews.instructions_request()),
    responses: [
      ok: {"Sent", "application/json", PaleeWeb.Schemas.BoxReviews.instructions_response()},
      not_found: @error,
      unprocessable_entity: @error
    ]
  )

  def send_instructions(conn, %{"id" => id}) do
    with {:ok, result} <-
           SiteAdmin.send_instructions(conn.assigns.tenant_context, id, conn.body_params),
         do: json(conn, result)
  end

  # ── Translations (ADR-520) ──────────────────────────────────────────────

  operation(:translations,
    summary: "«Μεταφράσεις»: every text of the website with its translation and status",
    parameters: [
      %Parameter{name: :locale, in: :query, required: true, schema: S.translation_locale()}
    ],
    responses: [
      ok: {"Translations", "application/json", S.translations_response()},
      unprocessable_entity: @error
    ]
  )

  def translations(conn, params) do
    with {:ok, page} <- SiteTranslations.show(conn.assigns.tenant_context, params["locale"]),
         do: json(conn, page)
  end

  operation(:save_translations,
    summary: "Save translations a person wrote (an empty text removes one); live at once",
    request_body: S.body(S.translations_save_request()),
    responses: [
      ok: {"Translations", "application/json", S.translations_response()},
      unprocessable_entity: @error
    ]
  )

  def save_translations(conn, _params) do
    body = conn.body_params

    with {:ok, page} <-
           SiteTranslations.save(conn.assigns.tenant_context, body.locale, body.entries),
         do: json(conn, page)
  end

  operation(:keep_translations,
    summary: "«Εντάξει, κράτα το»: keep machine or out-of-date translations as they are",
    request_body: S.body(S.translations_keep_request()),
    responses: [
      ok: {"Translations", "application/json", S.translations_response()},
      unprocessable_entity: @error
    ]
  )

  def keep_translations(conn, _params) do
    body = conn.body_params

    with {:ok, page} <-
           SiteTranslations.keep(conn.assigns.tenant_context, body.locale, body.keys),
         do: json(conn, page)
  end

  operation(:machine_translations,
    summary: "«Αυτόματη μετάφραση»: fill every missing or out-of-date text by machine",
    request_body: S.body(S.translations_machine_request()),
    responses: [
      ok: {"Translations", "application/json", S.translations_response()},
      unprocessable_entity: @error,
      service_unavailable: @error
    ]
  )

  def machine_translations(conn, _params) do
    with {:ok, page} <-
           SiteTranslations.machine_translate(
             conn.assigns.tenant_context,
             conn.body_params.locale
           ),
         do: json(conn, page)
  end
end

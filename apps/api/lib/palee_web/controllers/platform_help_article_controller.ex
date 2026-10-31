defmodule PaleeWeb.PlatformHelpArticleController do
  @moduledoc """
  ADR-362, vendor console › «Κέντρο βοήθειας»: the Palee team writes the
  help articles (one locale at a time), publishes them and rebuilds the
  search index.
  """

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias OpenApiSpex.{Parameter, Schema}
  alias Palee.Application.HelpCentre.PlatformHelpArticles
  alias PaleeWeb.Schemas.AiHelp, as: S

  action_fallback PaleeWeb.FallbackController

  tags(["Platform help centre"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  @slug %Parameter{name: :slug, in: :path, required: true, schema: %Schema{type: :string, maxLength: 80}}
  @locale %Parameter{
    name: :locale,
    in: :path,
    required: true,
    schema: %Schema{type: :string, enum: Palee.HelpCentre.locales()}
  }

  operation(:index,
    summary: "Every help article in every locale, drafts too (vendors)",
    parameters: [
      %Parameter{name: :locale, in: :query, required: false, schema: %Schema{type: :string, enum: Palee.HelpCentre.locales()}},
      %Parameter{name: :status, in: :query, required: false, schema: %Schema{type: :string, enum: Palee.HelpCentre.statuses()}},
      %Parameter{name: :slug, in: :query, required: false, schema: %Schema{type: :string, maxLength: 80}}
    ],
    responses: [ok: {"Articles", "application/json", S.console_articles()}]
  )

  def index(conn, params) do
    with {:ok, result} <- PlatformHelpArticles.list(conn.assigns.platform_context, params),
         do: json(conn, result)
  end

  operation(:save,
    summary: "Write one locale of a help article (creates it when new)",
    parameters: [@slug, @locale],
    request_body: S.body(S.help_article_request()),
    responses: [ok: {"Article", "application/json", S.console_article()}]
  )

  def save(conn, %{slug: slug, locale: locale}) do
    with {:ok, article} <-
           PlatformHelpArticles.save(conn.assigns.platform_context, slug, locale, conn.body_params),
         do: json(conn, article)
  end

  operation(:delete,
    summary: "Delete one locale of a help article",
    parameters: [@slug, @locale],
    responses: [ok: {"Deleted", "application/json", S.flag("HelpArticleDeleted", :deleted)}]
  )

  def delete(conn, %{slug: slug, locale: locale}) do
    with {:ok, result} <- PlatformHelpArticles.delete(conn.assigns.platform_context, slug, locale),
         do: json(conn, result)
  end

  operation(:reindex,
    summary: "Rebuild the help search index from the published articles",
    responses: [ok: {"Reindexed", "application/json", S.flag("HelpArticlesReindexed", :reindexed)}]
  )

  def reindex(conn, _params) do
    with {:ok, result} <- PlatformHelpArticles.reindex(conn.assigns.platform_context),
         do: json(conn, result)
  end
end

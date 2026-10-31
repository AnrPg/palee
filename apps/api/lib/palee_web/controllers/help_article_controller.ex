defmodule PaleeWeb.HelpArticleController do
  @moduledoc """
  ADR-362, the public help centre: search, the articles of one screen (the
  «?» of a staff screen) and one article. No sign-in; published articles
  only, in the reader's locale or else in English (`fallback`).
  """

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias OpenApiSpex.{Parameter, Schema}
  alias Palee.Application.HelpCentre.HelpArticles
  alias PaleeWeb.Schemas.AiHelp, as: S

  action_fallback PaleeWeb.FallbackController

  tags(["Help centre"])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  @locale %Parameter{
    name: :locale,
    in: :query,
    required: false,
    description: "One of the 12 app locales; default en",
    schema: %Schema{type: :string, maxLength: 10}
  }

  @audience %Parameter{
    name: :audience,
    in: :query,
    required: false,
    schema: %Schema{type: :string, enum: ["staff", "member"]}
  }

  @limit %Parameter{
    name: :limit,
    in: :query,
    required: false,
    schema: %Schema{type: :integer, minimum: 1, maximum: 20}
  }

  operation(:index,
    summary: "Search the help centre",
    security: [],
    parameters: [
      %Parameter{
        name: :q,
        in: :query,
        required: false,
        schema: %Schema{type: :string, maxLength: 200}
      },
      @locale,
      @audience,
      %Parameter{
        name: :screen,
        in: :query,
        required: false,
        description: "The app path the reader is on; its articles rank first",
        schema: %Schema{type: :string, maxLength: 300}
      },
      %Parameter{
        name: :feature,
        in: :query,
        required: false,
        schema: %Schema{type: :string, maxLength: 48}
      },
      @limit
    ],
    responses: [ok: {"Articles", "application/json", S.help_articles()}]
  )

  def index(conn, params) do
    with {:ok, result} <- HelpArticles.search(params), do: json(conn, result)
  end

  operation(:screen,
    summary: "The help articles linked from one app screen",
    security: [],
    parameters: [
      %Parameter{
        name: :path,
        in: :query,
        required: true,
        schema: %Schema{type: :string, maxLength: 300}
      },
      @locale,
      @audience,
      @limit
    ],
    responses: [ok: {"Articles", "application/json", S.help_articles()}]
  )

  def screen(conn, params) do
    params = params |> Map.put(:screen, Map.get(params, :path)) |> Map.delete(:path)
    with {:ok, result} <- HelpArticles.for_screen(params), do: json(conn, result)
  end

  operation(:show,
    summary: "One help article, in the locale or else in English",
    security: [],
    parameters: [
      %Parameter{
        name: :slug,
        in: :path,
        required: true,
        schema: %Schema{type: :string, maxLength: 80}
      },
      @locale
    ],
    responses: [ok: {"Article", "application/json", S.help_article()}]
  )

  def show(conn, %{slug: slug} = params) do
    with {:ok, article} <- HelpArticles.show(slug, Map.get(params, :locale)),
         do: json(conn, article)
  end
end

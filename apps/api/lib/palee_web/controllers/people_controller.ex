defmodule PaleeWeb.PeopleController do
  @moduledoc """
  A person's profile, the posts you may read, its media grid and badges
  (ADR-142, ADR-231, ADR-554), and your own profile card.
  """

  use PaleeWeb, :controller
  use PaleeWeb.ControllerSpecs

  alias Palee.Application.{PeopleSearch, SocialProfile}
  alias PaleeWeb.Schemas.Social, as: S
  alias OpenApiSpex.{Parameter, Schema}

  action_fallback PaleeWeb.FallbackController

  tags(["Follows"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  @id %Parameter{name: :id, in: :path, required: true, schema: S.uuid()}

  operation(:search,
    summary:
      "ADR-193: find people by @handle or name (shared clubs, Buddies, follows, nearby, public)",
    parameters: [
      %Parameter{
        name: :q,
        in: :query,
        required: true,
        schema: %Schema{type: :string, minLength: 1, maxLength: 80}
      }
    ],
    responses: [ok: {"People", "application/json", S.people_search_response()}]
  )

  def search(conn, %{q: query}) do
    with {:ok, result} <- PeopleSearch.call(conn.assigns.user_context, query),
         do: json(conn, result)
  end

  operation(:show,
    summary: "A person: name, avatar, counts and both follow relationships",
    parameters: [@id],
    responses: [ok: {"Person", "application/json", S.person_response()}]
  )

  def show(conn, %{id: id}) do
    with {:ok, person} <- SocialProfile.person(conn.assigns.user_context, id),
         do: json(conn, person)
  end

  operation(:posts,
    summary: "A person's followers and public posts you may read",
    parameters: [
      @id,
      %Parameter{name: :cursor, in: :query, required: false, schema: %Schema{type: :string}}
    ],
    responses: [ok: {"Posts", "application/json", S.person_posts_response()}]
  )

  def posts(conn, %{id: id} = params) do
    with {:ok, page} <- SocialProfile.posts(conn.assigns.user_context, id, params),
         do: json(conn, page)
  end

  operation(:media,
    summary: "ADR-231: the «Πολυμέσα» grid, a person's posts with photos or a video you may read",
    parameters: [
      @id,
      %Parameter{name: :cursor, in: :query, required: false, schema: %Schema{type: :string}}
    ],
    responses: [ok: {"Posts", "application/json", S.person_posts_response()}]
  )

  def media(conn, %{id: id} = params) do
    with {:ok, page} <- SocialProfile.media(conn.assigns.user_context, id, params),
         do: json(conn, page)
  end

  operation(:badges,
    summary: "ADR-554: the «Διακρίσεις» tab, a person's badges you may see",
    parameters: [@id],
    responses: [ok: {"Badges", "application/json", S.profile_badges_response()}]
  )

  def badges(conn, %{id: id}) do
    with {:ok, result} <- SocialProfile.badges(conn.assigns.user_context, id),
         do: json(conn, result)
  end

  operation(:update_card,
    summary: "ADR-554: your «Λίγα λόγια» and the optional tabs of your profile",
    request_body: S.body(S.profile_card_request()),
    responses: [ok: {"Card", "application/json", S.profile_card()}]
  )

  def update_card(conn, _params) do
    with {:ok, card} <- SocialProfile.put_card(conn.assigns.user_context, conn.body_params),
         do: json(conn, card)
  end
end

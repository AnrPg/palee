defmodule PaleeWeb.MyProgrammeController do
  @moduledoc """
  A buyer's programmes at a business (ADR-371): terms, buying on the
  business's provider page, what they bought, withdrawal and reviews.
  The store apps never call `buy` (ADR-256: digital services only).
  """

  use PaleeWeb, :controller
  use PaleeWeb.ControllerSpecs

  alias Palee.Application.Programmes.Buying
  alias PaleeWeb.Schemas.Programmes, as: S
  alias OpenApiSpex.{Parameter, Schema}

  action_fallback PaleeWeb.FallbackController

  tags(["Me"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  @id %Parameter{
    name: :id,
    in: :path,
    required: true,
    schema: %Schema{type: :string, format: :uuid}
  }
  @language %Parameter{
    name: :language,
    in: :query,
    required: false,
    schema: %Schema{type: :string, enum: ~w(el en)}
  }
  @refused [
    not_found: {"No such programme or purchase", "application/json", S.error()},
    conflict: {"Not possible now", "application/json", S.error()},
    unprocessable_entity: {"Invalid request", "application/json", S.error()}
  ]

  operation(:terms,
    summary: "What buying a programme costs and the texts the buyer agrees to",
    parameters: [@id, @language],
    responses: [ok: {"Terms", "application/json", S.terms_response()}] ++ @refused
  )

  def terms(conn, %{id: id} = params) do
    with {:ok, terms} <- Buying.terms(conn.assigns.tenant_context, id, params[:language]),
         do: json(conn, terms)
  end

  operation(:buy,
    summary: "Buy a programme: opens the business's provider checkout",
    description:
      "Nothing is delivered before the provider confirms the money; then the programme's " <>
        "WODs are scheduled from the start date.",
    parameters: [@id],
    request_body: S.body(S.buy_input()),
    responses: [ok: {"Checkout", "application/json", S.buy_response()}] ++ @refused
  )

  def buy(conn, %{id: id}) do
    with {:ok, result} <- Buying.buy(conn.assigns.tenant_context, id, conn.body_params),
         do: json(conn, result)
  end

  operation(:index,
    summary: "The programmes you bought here, with what giving one up returns",
    responses: [ok: {"Purchases", "application/json", S.purchase_list()}]
  )

  def index(conn, _params), do: json(conn, %{purchases: Buying.mine(conn.assigns.tenant_context)})

  operation(:show,
    summary: "One programme you bought, with its dated WODs",
    parameters: [@id],
    responses: [ok: {"Purchase", "application/json", S.purchase_response()}] ++ @refused
  )

  def show(conn, %{id: id}) do
    with {:ok, purchase} <- Buying.show(conn.assigns.tenant_context, id),
         do: json(conn, %{purchase: purchase})
  end

  operation(:withdraw,
    summary: "Give a programme up and get back what the rules give",
    parameters: [@id],
    responses: [ok: {"Refund", "application/json", S.refund_response()}] ++ @refused
  )

  def withdraw(conn, %{id: id}) do
    with {:ok, result} <- Buying.withdraw(conn.assigns.tenant_context, id), do: json(conn, result)
  end

  operation(:review,
    summary: "Review a programme you bought (once it started); again to change it",
    parameters: [@id],
    request_body: S.body(S.review_input()),
    responses: [ok: {"Review", "application/json", S.review_response()}] ++ @refused
  )

  def review(conn, %{id: id}) do
    with {:ok, review} <- Buying.review(conn.assigns.tenant_context, id, conn.body_params),
         do: json(conn, %{review: review})
  end
end

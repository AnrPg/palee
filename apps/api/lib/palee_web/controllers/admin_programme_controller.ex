defmodule PaleeWeb.AdminProgrammeController do
  @moduledoc """
  Staff write, publish and sell training programmes, follow their buyers,
  refund and moderate reviews (ADR-370/371).
  """

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Palee.Application.Programmes.Studio
  alias PaleeWeb.Schemas.Programmes, as: S
  alias OpenApiSpex.{Parameter, Schema}

  action_fallback PaleeWeb.FallbackController

  tags(["Admin Programmes"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  @id %Parameter{
    name: :id,
    in: :path,
    required: true,
    schema: %Schema{type: :string, format: :uuid}
  }
  @refused [
    not_found: {"No such programme, purchase or review", "application/json", S.error()},
    conflict: {"The programme can't take this step now", "application/json", S.error()},
    unprocessable_entity: {"Invalid programme", "application/json", S.error()}
  ]

  operation(:index,
    summary: "The business's programmes with sales and ratings",
    responses: [ok: {"Programmes", "application/json", S.staff_list()}]
  )

  def index(conn, _params),
    do: json(conn, %{programmes: Studio.list(conn.assigns.tenant_context)})

  operation(:create,
    summary: "Start a programme (a draft)",
    request_body: S.body(S.programme_input([:title])),
    responses: [created: {"Programme", "application/json", S.staff_response()}] ++ @refused
  )

  def create(conn, _params) do
    with {:ok, programme} <- Studio.create(conn.assigns.tenant_context, conn.body_params) do
      conn |> put_status(:created) |> json(%{programme: programme})
    end
  end

  operation(:show,
    summary: "One programme with its versions, sales and ratings",
    parameters: [@id],
    responses: [ok: {"Programme", "application/json", S.staff_response()}] ++ @refused
  )

  def show(conn, %{id: id}) do
    with {:ok, programme} <- Studio.show(conn.assigns.tenant_context, id),
         do: json(conn, %{programme: programme})
  end

  operation(:update,
    summary: "Change a programme or its draft days",
    description:
      "Title, price, listing and the refund rule apply to later buyers only. The days " <>
        "reach buyers only when published as a new version.",
    parameters: [@id],
    request_body: S.body(S.programme_input()),
    responses: [ok: {"Programme", "application/json", S.staff_response()}] ++ @refused
  )

  def update(conn, %{id: id}) do
    with {:ok, programme} <- Studio.update(conn.assigns.tenant_context, id, conn.body_params),
         do: json(conn, %{programme: programme})
  end

  operation(:publish,
    summary: "Publish the draft days as the next version and put the programme on sale",
    description:
      "Each WOD is frozen as a hidden copy, so later edits never change what buyers paid for. " <>
        "Buyers keep the version they bought.",
    parameters: [@id],
    request_body: S.body(S.publish_input()),
    responses: [ok: {"Programme", "application/json", S.staff_response()}] ++ @refused
  )

  def publish(conn, %{id: id}) do
    with {:ok, programme} <- Studio.publish(conn.assigns.tenant_context, id, conn.body_params),
         do: json(conn, %{programme: programme})
  end

  operation(:archive,
    summary: "Stop selling a programme (buyers keep it)",
    parameters: [@id],
    responses: [ok: {"Programme", "application/json", S.staff_response()}] ++ @refused
  )

  def archive(conn, %{id: id}) do
    with {:ok, programme} <- Studio.archive(conn.assigns.tenant_context, id),
         do: json(conn, %{programme: programme})
  end

  operation(:restore,
    summary: "Sell an archived programme again",
    parameters: [@id],
    responses: [ok: {"Programme", "application/json", S.staff_response()}] ++ @refused
  )

  def restore(conn, %{id: id}) do
    with {:ok, programme} <- Studio.restore(conn.assigns.tenant_context, id),
         do: json(conn, %{programme: programme})
  end

  operation(:purchases,
    summary: "Who bought a programme, newest first",
    parameters: [@id],
    responses: [ok: {"Purchases", "application/json", S.purchase_list()}] ++ @refused
  )

  def purchases(conn, %{id: id}) do
    with {:ok, purchases} <- Studio.purchases(conn.assigns.tenant_context, id),
         do: json(conn, %{purchases: purchases})
  end

  operation(:refund,
    summary: "Refund a buyer through the business's provider",
    description:
      "Up to what is left of the price. A full refund ends the purchase and removes its future WODs.",
    parameters: [@id],
    request_body: S.body(S.refund_input()),
    responses: [ok: {"Refund", "application/json", S.refund_response()}] ++ @refused
  )

  def refund(conn, %{id: id}) do
    with {:ok, result} <- Studio.refund(conn.assigns.tenant_context, id, conn.body_params),
         do: json(conn, result)
  end

  operation(:reviews,
    summary: "Every review of a programme, hidden ones included",
    parameters: [@id],
    responses: [ok: {"Reviews", "application/json", S.review_list()}] ++ @refused
  )

  def reviews(conn, %{id: id}) do
    with {:ok, reviews} <- Studio.reviews(conn.assigns.tenant_context, id),
         do: json(conn, %{reviews: reviews})
  end

  operation(:moderate_review,
    summary: "Hide a review with a reason, or show it again",
    description: "Reviews are never edited or deleted by the business.",
    parameters: [@id],
    request_body: S.body(S.moderation_input()),
    responses: [ok: {"Review", "application/json", S.review_response()}] ++ @refused
  )

  def moderate_review(conn, %{id: id}) do
    with {:ok, review} <-
           Studio.moderate_review(
             conn.assigns.tenant_context,
             id,
             conn.body_params[:hidden_reason]
           ),
         do: json(conn, %{review: review})
  end
end

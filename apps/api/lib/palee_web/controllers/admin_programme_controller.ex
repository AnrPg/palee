defmodule PaleeWeb.AdminProgrammeController do
  @moduledoc """
  Staff write, publish and sell training programmes, follow their buyers,
  refund and moderate reviews (ADR-370/371).
  """

  use PaleeWeb, :controller
  use PaleeWeb.ControllerSpecs

  alias Palee.Application.{CompleteMediaUpload, RequestMediaUpload}
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

  # ── Cover (ADR-541) ─────────────────────────────────────────────────────

  operation(:cover_upload,
    summary: "Reserve a cover photo (programme_cover) and get a presigned upload for it",
    description:
      "Upload the original photo and the cover rendered from it (16:9) the same way, then " <>
        "set them on the programme.",
    request_body: S.body(PaleeWeb.Schemas.Media.upload_request()),
    responses: [ok: {"Upload", "application/json", PaleeWeb.Schemas.Media.upload()}] ++ @refused
  )

  def cover_upload(conn, _params) do
    with {:ok, upload} <-
           RequestMediaUpload.call(
             conn.assigns.tenant_context,
             "programme_cover",
             conn.body_params
           ),
         do: json(conn, upload)
  end

  operation(:complete_cover,
    summary: "Verify an uploaded cover photo (type, size, no metadata) and mark it ready",
    parameters: [@id],
    responses:
      [ok: {"Media", "application/json", PaleeWeb.Schemas.Media.media_response()}] ++ @refused
  )

  def complete_cover(conn, %{id: id}) do
    with {:ok, media} <-
           CompleteMediaUpload.call(conn.assigns.tenant_context, "programme_cover", id),
         do: json(conn, %{media: media})
  end

  operation(:set_cover,
    summary: "Set the programme's cover: the rendered 16:9 image, its original and the edit",
    description:
      "Editing again starts from the original with the stored edit. The replaced uploads are " <>
        "deleted.",
    parameters: [@id],
    request_body: S.body(S.cover_input()),
    responses: [ok: {"Programme", "application/json", S.staff_response()}] ++ @refused
  )

  def set_cover(conn, %{id: id}) do
    with {:ok, programme} <- Studio.set_cover(conn.assigns.tenant_context, id, conn.body_params),
         do: json(conn, %{programme: programme})
  end

  operation(:remove_cover,
    summary: "Remove the cover: the page shows the theme colour strip again",
    parameters: [@id],
    responses: [ok: {"Programme", "application/json", S.staff_response()}] ++ @refused
  )

  def remove_cover(conn, %{id: id}) do
    with {:ok, programme} <- Studio.remove_cover(conn.assigns.tenant_context, id),
         do: json(conn, %{programme: programme})
  end
end

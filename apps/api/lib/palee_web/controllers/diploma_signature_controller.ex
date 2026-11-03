defmodule PaleeWeb.DiplomaSignatureController do
  @moduledoc """
  «Υπογραφή για διπλώματα» (ADR-377 addendum, option Γ): the signed-in
  coach's own signature image for diplomas. Only its owner reads, replaces
  or removes it; the image is never served to anyone else (it is only drawn
  inside diploma PDFs).
  """

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Palee.Application.DiplomaSignatures
  alias PaleeWeb.Schemas.DiplomaSignature, as: S

  action_fallback PaleeWeb.FallbackController

  tags(["Ranks"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  @statuses %{
    forbidden: {:forbidden, "Only staff who award ranks keep a diploma signature"},
    invalid_signature_image: {:unprocessable_entity, "Choose a PNG or JPEG image"},
    signature_unsupported_type: {:unprocessable_entity, "Choose a PNG or JPEG image"},
    signature_too_large: {:unprocessable_entity, "The image is too large"},
    signature_too_small: {:unprocessable_entity, "The image is too small"},
    signature_dimensions_too_large: {:unprocessable_entity, "The image has too many pixels"},
    not_found: {:not_found, "No signature"},
    storage_unavailable: {:service_unavailable, "Storage is unavailable; try again."}
  }

  operation(:show,
    summary: "My diploma signature, whether I can keep one, and the limits",
    responses: [ok: {"Signature", "application/json", S.show_response()}]
  )

  def show(conn, _params) do
    with {:ok, result} <- DiplomaSignatures.show(conn.assigns.user_context),
         do: json(conn, result)
  end

  operation(:create,
    summary: "Set or replace my diploma signature (PNG or JPEG, base64)",
    request_body: {"Image", "application/json", S.upload_request(), required: true},
    responses: [
      ok: {"Stored", "application/json", S.upload_response()},
      forbidden: {"Not staff who award ranks", "application/json", S.error()},
      unprocessable_entity: {"Unusable image", "application/json", S.error()},
      service_unavailable: {"Storage unavailable", "application/json", S.error()}
    ]
  )

  def create(conn, _params) do
    conn.assigns.user_context
    |> DiplomaSignatures.put(conn.body_params)
    |> respond(conn, &json(conn, &1))
  end

  operation(:image,
    summary: "My own diploma signature image (for the preview; never anyone else's)",
    responses: [
      ok: {"Image", "image/png", S.image()},
      not_found: {"No signature", "application/json", S.error()}
    ]
  )

  def image(conn, _params) do
    conn.assigns.user_context
    |> DiplomaSignatures.image()
    |> respond(conn, fn %{content_type: type, data: data} ->
      conn
      |> put_resp_content_type(type, nil)
      |> put_resp_header("cache-control", "private, no-store")
      |> put_resp_header("x-content-type-options", "nosniff")
      |> send_resp(200, data)
    end)
  end

  operation(:delete,
    summary: "Remove my diploma signature (diplomas drawn afterwards show an empty line)",
    responses: [no_content: {"Removed", "application/json", S.error()}]
  )

  def delete(conn, _params) do
    :ok = DiplomaSignatures.remove(conn.assigns.user_context)
    send_resp(conn, :no_content, "")
  end

  defp respond({:ok, result}, _conn, fun), do: fun.(result)

  defp respond({:error, reason}, conn, _fun) when is_map_key(@statuses, reason) do
    {status, message} = Map.fetch!(@statuses, reason)
    code = Atom.to_string(reason)
    conn |> put_status(status) |> json(%{code: code, error: message})
  end

  defp respond({:error, _reason} = error, _conn, _fun), do: error
end

defmodule PaleeWeb.AdminPackageAudienceController do
  @moduledoc "ADR-553: «Ποιος βλέπει τα πακέτα» (Πακέτα συνδρομής), the box's and each package's."

  use PaleeWeb, :controller
  use PaleeWeb.ControllerSpecs

  alias Palee.Application.Payments.PackageAudience
  alias PaleeWeb.Schemas.PackageAudience, as: S
  alias OpenApiSpex.{Parameter, Schema}

  action_fallback PaleeWeb.FallbackController

  tags(["Package audience"])
  security([%{"bearerAuth" => []}])

  @id %Parameter{
    name: :id,
    in: :path,
    required: true,
    schema: %Schema{type: :string, format: :uuid}
  }
  @refused [
    not_found:
      {"No such package, person or exception", "application/json", %Schema{type: :object}},
    unprocessable_entity: {"Invalid choice", "application/json", %Schema{type: :object}}
  ]

  operation(:show,
    summary: "Who sees the box's packages, and the person exceptions",
    responses: [ok: {"Settings", "application/json", S.settings()}]
  )

  def show(conn, _params) do
    with {:ok, settings} <- PackageAudience.settings(conn.assigns.tenant_context),
         do: json(conn, settings)
  end

  operation(:update,
    summary: "The box's choice: all, own (each person only theirs) or none",
    request_body: {"Choice", "application/json", S.box_request()},
    responses: [ok: {"Settings", "application/json", S.settings()}] ++ @refused
  )

  def update(conn, params) do
    with {:ok, settings} <-
           PackageAudience.set_box(conn.assigns.tenant_context, params["audience"]),
         do: json(conn, settings)
  end

  operation(:update_package,
    summary: "A package's own choice; null follows the box",
    parameters: [@id],
    request_body: {"Choice", "application/json", S.package_request()},
    responses: [ok: {"Package", "application/json", S.package_response()}] ++ @refused
  )

  def update_package(conn, %{"id" => id} = params) do
    with {:ok, package} <-
           PackageAudience.set_package(conn.assigns.tenant_context, id, params["audience"]),
         do: json(conn, package)
  end

  operation(:put_exception,
    summary: "Always show (show) or never show (hide) one person a package or every package",
    request_body: {"Exception", "application/json", S.exception_request()},
    responses: [ok: {"Settings", "application/json", S.settings()}] ++ @refused
  )

  def put_exception(conn, params) do
    with {:ok, settings} <- PackageAudience.put_exception(conn.assigns.tenant_context, params),
         do: json(conn, settings)
  end

  operation(:delete_exception,
    summary: "Removes a person exception",
    parameters: [@id],
    responses: [ok: {"Settings", "application/json", S.settings()}] ++ @refused
  )

  def delete_exception(conn, %{"id" => id}) do
    with {:ok, settings} <- PackageAudience.delete_exception(conn.assigns.tenant_context, id),
         do: json(conn, settings)
  end
end

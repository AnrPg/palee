defmodule PaleeWeb.AdminMemberBenefitController do
  @moduledoc "ADR-612: «Δώρο ή χάρη» on a member's profile, and its history."

  use PaleeWeb, :controller
  use PaleeWeb.ControllerSpecs

  alias Palee.Application.MemberBenefits
  alias PaleeWeb.Schemas.MemberBenefits, as: S
  alias OpenApiSpex.{Parameter, Schema}

  action_fallback PaleeWeb.FallbackController

  tags(["Member benefits"])
  security([%{"bearerAuth" => []}])

  @user %Parameter{
    name: :id,
    in: :path,
    required: true,
    description: "The member's user id",
    schema: %Schema{type: :string, format: :uuid}
  }
  @benefit %Parameter{
    name: :benefit_id,
    in: :path,
    required: true,
    schema: %Schema{type: :string, format: :uuid}
  }
  @refused [
    unprocessable_entity: {"Not valid", "application/json", %Schema{type: :object}},
    conflict: {"Not possible now", "application/json", %Schema{type: :object}},
    not_found: {"No such member or benefit", "application/json", %Schema{type: :object}}
  ]

  operation(:index,
    summary: "What the box gave a member for free, newest first",
    parameters: [@user],
    responses: [ok: {"Benefits", "application/json", S.list_response()}]
  )

  def index(conn, %{"id" => user_id}) do
    with {:ok, result} <- MemberBenefits.list(conn.assigns.tenant_context, user_id),
         do: json(conn, result)
  end

  operation(:create,
    summary: "Give a member a grace, free access, extra uses, a package or a forgiven debt",
    parameters: [@user],
    request_body: {"Benefit", "application/json", S.grant_body()},
    responses:
      [
        created: {"Benefit", "application/json", S.one_response()},
        ok: {"Already given (same idempotency key)", "application/json", S.one_response()}
      ] ++ @refused
  )

  def create(conn, %{"id" => user_id}) do
    with {:ok, result} <-
           MemberBenefits.grant(conn.assigns.tenant_context, user_id, conn.body_params || %{}) do
      conn
      |> put_status(if(result.replayed, do: :ok, else: :created))
      |> json(result)
    end
  end

  operation(:revoke,
    summary: "Revoke a grace, free access or extra uses",
    parameters: [@user, @benefit],
    request_body: {"Revocation", "application/json", S.revoke_body()},
    responses: [ok: {"Benefit", "application/json", S.one_response()}] ++ @refused
  )

  def revoke(conn, %{"id" => user_id, "benefit_id" => benefit_id}) do
    with {:ok, result} <-
           MemberBenefits.revoke(
             conn.assigns.tenant_context,
             user_id,
             benefit_id,
             conn.body_params || %{}
           ),
         do: json(conn, result)
  end
end

defmodule PaleeWeb.MyMembershipController do
  @moduledoc "ADR-220: the member's renewal choice; ADR-595: leaving the box."
  use PaleeWeb, :controller
  use PaleeWeb.ControllerSpecs

  alias OpenApiSpex.Schema
  alias Palee.Application.MembershipRenewal

  action_fallback PaleeWeb.FallbackController

  tags(["Member Finance"])
  security([%{"bearerAuth" => []}])

  @open_object %Schema{type: :object, additionalProperties: true}

  operation(:set_auto_renew,
    summary: "Turn renewal of one of my subscriptions on or off",
    parameters: [
      id: [in: :path, required: true, schema: %Schema{type: :string, format: :uuid}]
    ],
    request_body:
      {"Renewal choice", "application/json",
       %Schema{
         type: :object,
         properties: %{auto_renew: %Schema{type: :boolean}},
         required: [:auto_renew]
       }},
    responses: [
      ok: {"Package subscription", "application/json", @open_object},
      conflict: {"Ended, or leaving the box", "application/json", @open_object},
      unprocessable_entity: {"No renewal choice here", "application/json", @open_object}
    ]
  )

  def set_auto_renew(conn, %{"id" => id}) do
    with {:ok, subscription} <-
           MembershipRenewal.member_set_auto_renew(
             conn.assigns.tenant_context,
             id,
             body(conn)["auto_renew"]
           ) do
      json(conn, %{package_subscription: subscription})
    end
  end

  operation(:leave,
    summary:
      "Leave the box now (ADR-595): no longer a member; a package I have stays usable to its last day, money owed stays owed",
    request_body:
      {"Leave", "application/json",
       %Schema{
         type: :object,
         properties: %{reason: %Schema{type: :string, maxLength: 500, nullable: true}}
       }},
    responses: [
      ok: {"Leave result", "application/json", @open_object},
      conflict: {"Already leaving", "application/json", @open_object}
    ]
  )

  def leave(conn, _params) do
    with {:ok, result} <- MembershipRenewal.member_leave(conn.assigns.tenant_context, body(conn)) do
      json(conn, result)
    end
  end

  defp body(%{body_params: %Plug.Conn.Unfetched{}}), do: %{}
  defp body(%{body_params: params}) when is_map(params), do: params
  defp body(_conn), do: %{}
end

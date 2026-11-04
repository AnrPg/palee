defmodule PaleeWeb.AdminMemberRiskController do
  @moduledoc """
  ADR-347: «Σε κίνδυνο»: box members who may be about to leave, why, and
  what to do; «Μίλησα» and «Το είδα».
  """

  use PaleeWeb, :controller
  use PaleeWeb.ControllerSpecs

  alias OpenApiSpex.{Parameter, Schema}
  alias Palee.Application.Retention.MembersAtRisk
  alias PaleeWeb.Growth.Params
  alias PaleeWeb.Schemas.Growth, as: G

  action_fallback PaleeWeb.FallbackController

  tags(["Admin Members at risk"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  @user_id %Parameter{name: :user_id, in: :path, required: true, schema: G.uuid()}
  @risk {"Member at risk", "application/json", G.one(:member, G.risk())}

  operation(:index,
    summary: "Box members at risk, highest score first, with reasons",
    parameters: [
      %Parameter{
        name: :level,
        in: :query,
        schema: %Schema{type: :string, enum: ["high", "medium", "all"]}
      },
      %Parameter{name: :include_snoozed, in: :query, schema: %Schema{type: :boolean}},
      %Parameter{
        name: :limit,
        in: :query,
        schema: %Schema{type: :integer, minimum: 1, maximum: 200}
      }
    ],
    responses: [ok: {"Members at risk", "application/json", G.risk_list()}]
  )

  def index(conn, params) do
    params =
      params
      |> Params.stringify()
      |> Map.new(fn {k, v} -> {k, if(is_integer(v), do: to_string(v), else: v)} end)

    json(conn, MembersAtRisk.list(context(conn), params))
  end

  operation(:show,
    summary: "One box member's risk with its reasons and what staff did (who and when, ADR-384)",
    parameters: [@user_id],
    responses: [
      ok: {"Member at risk with the staff action log", "application/json", G.risk_detail()}
    ]
  )

  def show(conn, %{user_id: user_id}) do
    with {:ok, detail} <- MembersAtRisk.show(context(conn), user_id), do: json(conn, detail)
  end

  operation(:contacted,
    summary: "«Μίλησα»: staff reached the member",
    parameters: [@user_id],
    request_body: G.body(G.risk_contacted_body()),
    responses: [ok: @risk]
  )

  def contacted(conn, %{user_id: user_id}) do
    with {:ok, risk} <-
           MembersAtRisk.contacted(context(conn), user_id, Params.stringify(conn.body_params)) do
      json(conn, %{member: risk})
    end
  end

  operation(:snooze,
    summary: "«Το είδα»: hide the member from the list for some days (0 shows them again)",
    parameters: [@user_id],
    request_body: G.body(G.risk_snooze_body()),
    responses: [ok: @risk]
  )

  def snooze(conn, %{user_id: user_id}) do
    with {:ok, risk} <-
           MembersAtRisk.snooze(context(conn), user_id, Params.stringify(conn.body_params)) do
      json(conn, %{member: risk})
    end
  end

  defp context(conn), do: conn.assigns.tenant_context
end

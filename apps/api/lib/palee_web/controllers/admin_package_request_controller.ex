defmodule PaleeWeb.AdminPackageRequestController do
  @moduledoc """
  ADR-291: the front desk's «Περιμένουν πληρωμή»: packages people asked for
  in the app («Το θέλω»), and «Είσπραξη», which records the money and
  assigns the package in one step.
  """

  use PaleeWeb, :controller
  use PaleeWeb.ControllerSpecs

  alias OpenApiSpex.{MediaType, Parameter, RequestBody, Schema}
  alias Palee.Application.{BranchReport, PackageRule}
  alias Palee.Application.Finance.PackageRequests
  alias PaleeWeb.Schemas.Payments, as: P

  action_fallback PaleeWeb.FallbackController

  tags(["Admin Finance"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  @id %Parameter{name: :id, in: :path, required: true, schema: P.uuid()}

  operation(:index,
    summary: "Packages waiting to be paid at the front desk",
    description:
      "Open requests (held `hold_days` days), oldest first, each with the person who asked.",
    parameters: [PaleeWeb.Schemas.LocationScope.filter_parameter()],
    responses: [ok: {"Package requests", "application/json", P.package_request_list()}]
  )

  def index(conn, params) do
    context = conn.assigns.tenant_context
    report = BranchReport.resolve(context, stringify(params))
    json(conn, %{requests: PackageRequests.for_desk(context, user_ids: report.user_ids)})
  end

  operation(:collect,
    summary: "Take the money for a package waiting at the desk («Είσπραξη»)",
    description:
      "Records the payment (the box's receipt or invoice, ADR-222) and assigns the package " <>
        "from today in one step. Safe to retry.",
    parameters: [@id],
    request_body: %RequestBody{
      required: true,
      content: %{"application/json" => %MediaType{schema: P.package_request_collect_body()}}
    },
    responses: [
      ok:
        {"Collected", "application/json",
         %Schema{
           type: :object,
           properties: %{
             request: P.package_request(),
             received: %Schema{type: :object, additionalProperties: true}
           },
           required: [:received, :request]
         }}
    ]
  )

  def collect(conn, %{id: id}) do
    with {:ok, result} <-
           PackageRequests.collect(
             conn.assigns.tenant_context,
             id,
             Guardian.Plug.current_resource(conn).id,
             conn.body_params
           ) do
      json(conn, result)
    end
  end

  operation(:activate_unpaid,
    summary: "Activate a package that waits at the desk, payment pending («Εκκρεμεί πληρωμή»)",
    description:
      "ADR-633: the package starts today at the price the person was shown and its charge " <>
        "is issued now, so payment reminders, grace days and the lock follow it. Safe to retry.",
    parameters: [@id],
    responses: [
      ok:
        {"Activated", "application/json",
         %Schema{
           type: :object,
           properties: %{
             request: P.package_request(),
             subscription_id: %{P.uuid() | nullable: true}
           },
           required: [:request]
         }}
    ]
  )

  def activate_unpaid(conn, %{id: id}) do
    with {:ok, result} <-
           PackageRequests.activate_unpaid(
             conn.assigns.tenant_context,
             id,
             Guardian.Plug.current_resource(conn).id
           ) do
      json(conn, result)
    end
  end

  operation(:decline,
    summary: "Decline a package that waits at the desk («Απόρριψη»)",
    description:
      "ADR-633: the reason is required and the person reads it; their upcoming class while " <>
        "waiting, if any, is cancelled.",
    parameters: [@id],
    request_body: %RequestBody{
      required: true,
      content: %{"application/json" => %MediaType{schema: P.package_request_decline_body()}}
    },
    responses: [
      ok:
        {"Declined", "application/json",
         %Schema{
           type: :object,
           properties: %{
             request: P.package_request(),
             cancelled_bookings: %Schema{type: :integer}
           },
           required: [:request, :cancelled_bookings]
         }}
    ]
  )

  def decline(conn, %{id: id}) do
    with {:ok, result} <-
           PackageRequests.decline(
             conn.assigns.tenant_context,
             id,
             Guardian.Plug.current_resource(conn).id,
             conn.body_params
           ) do
      json(conn, result)
    end
  end

  operation(:rollout,
    summary: "Who trains on the package rule's 14 days («Μετάβαση»)",
    description:
      "ADR-633: since when the box books only with a package, and the people who were " <>
        "training without one then, with their last free day and whether they have a package now.",
    responses: [ok: {"Rollout", "application/json", P.package_rule_rollout()}]
  )

  def rollout(conn, _params), do: json(conn, PackageRule.rollout(conn.assigns.tenant_context))

  defp stringify(params), do: Map.new(params, fn {key, value} -> {to_string(key), value} end)
end

defmodule PaleeWeb.MyFeaturesController do
  @moduledoc """
  ADR-470: which optional features this business has switched on (online
  and card payments, referrals, promotions, perks, trials, package
  modules). Every screen reads this one answer to hide what depends on a
  feature that is off. Booleans only, so any member may read it.
  """

  use PaleeWeb, :controller
  use PaleeWeb.ControllerSpecs

  alias OpenApiSpex.Schema
  alias Palee.Application.BusinessFeatures
  alias Palee.Organizations

  action_fallback PaleeWeb.FallbackController

  tags(["Organizations"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  @features_schema %Schema{
    title: "BusinessFeatures",
    type: :object,
    properties: %{
      features: %Schema{
        type: :object,
        description: "ADR-470: every feature key with whether it is on",
        properties: Map.new(BusinessFeatures.keys(), &{String.to_atom(&1), %Schema{type: :boolean}}),
        required: Enum.map(BusinessFeatures.keys(), &String.to_atom/1)
      }
    },
    required: [:features]
  }

  operation(:show,
    summary: "Which optional features this business has on",
    description:
      "ADR-470. With `location_ids` (a branch filter) a feature a branch can have on its own " <>
        "(promotions) counts only when it covers one of those branches.",
    parameters: [PaleeWeb.Schemas.LocationScope.filter_parameter()],
    responses: [ok: {"Features", "application/json", @features_schema}]
  )

  def show(conn, params) do
    location_ids =
      case Organizations.requested_location_ids(params) do
        [] -> nil
        ids -> ids
      end

    json(conn, %{features: BusinessFeatures.status(conn.assigns.tenant_context, location_ids)})
  end
end

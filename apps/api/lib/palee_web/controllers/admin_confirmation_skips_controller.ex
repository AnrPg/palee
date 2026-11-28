defmodule PaleeWeb.AdminConfirmationSkipsController do
  @moduledoc """
  ADR-795: «Να μην εμφανιστεί ξανά σήμερα» on the money questions
  («Έλαβες πραγματικά τα χρήματα;»). One skip per staff member, kind and
  box-local day, so it holds on every device of the account until the box's
  midnight.
  """

  use PaleeWeb, :controller
  use PaleeWeb.ControllerSpecs

  require Logger

  alias OpenApiSpex.Schema
  alias Palee.{Finance, Organizations}
  alias Palee.Finance.Domain.MoneyConfirmations

  action_fallback PaleeWeb.FallbackController

  tags(["Admin Finance"])
  security([%{"bearerAuth" => []}])

  @kind %Schema{type: :string, enum: MoneyConfirmations.kinds()}
  @skips %Schema{
    type: :object,
    properties: %{
      day: %Schema{type: :string, format: :date},
      skipped: %Schema{type: :array, items: @kind}
    },
    required: [:day, :skipped]
  }

  operation(:index,
    summary: "The money questions I chose not to see again today (box-local day)",
    responses: [ok: {"Skipped today", "application/json", @skips}]
  )

  def index(conn, _params) do
    context = conn.assigns.tenant_context
    day = Organizations.local_today(context.organization_id)
    json(conn, %{day: day, skipped: Finance.confirmation_skips(context, user_id(conn), day)})
  end

  operation(:create,
    summary: "«Να μην εμφανιστεί ξανά σήμερα» for one money question",
    request_body:
      {"Question", "application/json",
       %Schema{type: :object, properties: %{kind: @kind}, required: [:kind]}},
    responses: [
      ok: {"Skipped today", "application/json", @skips},
      unprocessable_entity:
        {"Unknown question", "application/json",
         %Schema{type: :object, additionalProperties: true}}
    ]
  )

  def create(conn, _params) do
    context = conn.assigns.tenant_context
    user_id = user_id(conn)
    day = Organizations.local_today(context.organization_id)
    kind = kind(conn.body_params)

    with :ok <- Finance.skip_confirmation(context, user_id, kind, day) do
      Logger.info(
        "confirmation_skipped organization_id=#{context.organization_id} user_id=#{user_id} " <>
          "kind=#{kind} day=#{day}"
      )

      json(conn, %{day: day, skipped: Finance.confirmation_skips(context, user_id, day)})
    end
  end

  defp kind(%{"kind" => kind}), do: kind
  defp kind(_body), do: nil

  defp user_id(conn) do
    case Guardian.Plug.current_resource(conn) do
      %{id: id} -> id
      _anonymous -> nil
    end
  end
end

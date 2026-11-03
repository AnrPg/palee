defmodule PaleeWeb.AdminCardSurchargeController do
  @moduledoc "Οικονομικά › Πληρωμές › the card surcharge passed on to the person paying (ADR-340)."

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Palee.Application.Payments.CardSurcharges
  alias PaleeWeb.Schemas.CardSurcharges, as: S

  action_fallback PaleeWeb.FallbackController

  tags(["Payments"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  operation(:show,
    summary: "The box's card surcharge and what the law of its country allows",
    description:
      "Off until the owner turns it on. `law` says which cards may carry a surcharge in " <>
        "the box's country (EU/EEA: commercial or non-EEA cards only; UK: commercial only; " <>
        "US/Canada: credit only, capped; elsewhere: none).",
    responses: [ok: {"Card surcharge", "application/json", S.status()}]
  )

  def show(conn, _params), do: json(conn, CardSurcharges.settings(conn.assigns.tenant_context))

  operation(:update,
    summary: "Choose whether and where the card fee is passed on",
    description:
      "Refused with `card_surcharge_not_allowed` where the law forbids it or above its cap.",
    request_body: S.body(S.settings_body()),
    responses: [ok: {"Card surcharge", "application/json", S.status()}]
  )

  def update(conn, _params) do
    with {:ok, status} <-
           CardSurcharges.save(conn.assigns.tenant_context, conn.body_params) do
      json(conn, status)
    end
  end

  operation(:quote,
    summary: "What a payment would carry, as shown before paying",
    request_body: S.body(S.quote_body()),
    responses: [ok: {"Quote", "application/json", S.quote()}]
  )

  def quote(conn, _params) do
    body = conn.body_params

    with {:ok, quote} <-
           CardSurcharges.quote(
             conn.assigns.tenant_context,
             body.channel,
             body.amount_cents,
             card(body[:card])
           ) do
      json(conn, quote)
    end
  end

  defp card(%{} = card), do: Map.take(card, [:funding, :country, :commercial])
  defp card(_none), do: %{}
end

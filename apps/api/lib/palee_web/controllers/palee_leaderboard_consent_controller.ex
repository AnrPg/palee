defmodule PaleeWeb.PaleeLeaderboardConsentController do
  @moduledoc """
  ADR-394: the person's own answer about the Palee-wide benchmark board
  («Όλο το Palee»), account level.
  """

  use PaleeWeb, :controller
  use PaleeWeb.ControllerSpecs

  alias Palee.Application.ManagePaleeLeaderboardConsent
  alias PaleeWeb.Schemas.TrainingFloor, as: S

  action_fallback PaleeWeb.FallbackController

  tags(["Leaderboards"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  operation(:show,
    summary: "Your answer about the Palee-wide benchmark board",
    responses: [ok: {"Answer", "application/json", S.palee_leaderboard_consent()}]
  )

  def show(conn, _params) do
    with {:ok, consent} <- ManagePaleeLeaderboardConsent.get(conn.assigns.user_context),
         do: json(conn, consent)
  end

  operation(:update,
    summary: "Put your score on the Palee-wide board (share) or only see your place (see_only)",
    request_body: S.body(S.palee_leaderboard_consent_request()),
    responses: [
      ok: {"Answer", "application/json", S.palee_leaderboard_consent()},
      unprocessable_entity: {"Unknown choice", "application/json", S.error()}
    ]
  )

  def update(conn, _params) do
    choice = Map.get(conn.body_params, :choice)

    with {:ok, consent} <- ManagePaleeLeaderboardConsent.put(conn.assigns.user_context, choice),
         do: json(conn, consent)
  end

  operation(:delete,
    summary: "Withdraw: leave every Palee-wide board at once",
    responses: [ok: {"Answer", "application/json", S.palee_leaderboard_consent()}]
  )

  def delete(conn, _params) do
    with {:ok, consent} <- ManagePaleeLeaderboardConsent.withdraw(conn.assigns.user_context),
         do: json(conn, consent)
  end
end

defmodule PaleeWeb.WorkoutLeaderboardController do
  @moduledoc """
  ADR-356 (CP-D2): a WOD's leaderboard with filters and a percentile per
  score, and the person's leaderboard profile at this box (division, birth
  year).
  """

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Palee.Application.{GetWorkoutLeaderboard, LeaderboardProfile}
  alias PaleeWeb.Schemas.TrainingFloor, as: S
  alias OpenApiSpex.Schema

  action_fallback PaleeWeb.FallbackController

  tags(["Leaderboards"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  operation(:show,
    summary: "A WOD's leaderboard, filtered, with a percentile for each score",
    parameters: [
      id: [in: :path, required: true, schema: %Schema{type: :string, format: :uuid}],
      division: [
        in: :query,
        required: false,
        description: "Only this division",
        schema: %Schema{type: :string, enum: ~w(women men)}
      ],
      age_group: [
        in: :query,
        required: false,
        description: "Only this age group (age reached during the year)",
        schema: %Schema{
          type: :string,
          enum: ~w(under_18 18_34 35_39 40_44 45_49 50_54 55_59 60_64 65_plus)
        }
      ],
      scale: [
        in: :query,
        required: false,
        description: "Only this scale level slug",
        schema: %Schema{type: :string, maxLength: 64}
      ],
      scope: [
        in: :query,
        required: false,
        description: "Whole box, one branch, or every box (palee: only a benchmark WOD, ADR-394)",
        schema: %Schema{type: :string, enum: ~w(box branch palee)}
      ],
      location_id: [
        in: :query,
        required: false,
        description: "The branch, with scope=branch",
        schema: %Schema{type: :string, format: :uuid}
      ],
      window: [
        in: :query,
        required: false,
        description: "Time window around `date` (default day)",
        schema: %Schema{type: :string, enum: ~w(day week month year all)}
      ],
      date: [
        in: :query,
        required: false,
        description: "Gym date (default today)",
        schema: %Schema{type: :string, format: :date}
      ],
      buddies: [
        in: :query,
        required: false,
        description: "Only the viewer and their buddies",
        schema: %Schema{type: :boolean}
      ]
    ],
    responses: [
      ok: {"Leaderboard", "application/json", S.workout_leaderboard()},
      not_found: {"No such WOD", "application/json", S.error()},
      conflict:
        {"scope=palee before answering the Palee-wide question", "application/json", S.error()},
      unprocessable_entity: {"A filter does not read", "application/json", S.error()}
    ]
  )

  def show(conn, %{id: id} = params) do
    with {:ok, board} <-
           GetWorkoutLeaderboard.call(
             conn.assigns.tenant_context,
             id,
             Map.delete(params, :id) |> Map.delete(:organization_slug)
           ),
         do: json(conn, board)
  end

  operation(:profile,
    summary: "Your division and birth year for this box's leaderboards",
    responses: [ok: {"Profile", "application/json", S.leaderboard_profile()}]
  )

  def profile(conn, _params) do
    with {:ok, profile} <- LeaderboardProfile.get(conn.assigns.tenant_context),
         do: json(conn, profile)
  end

  operation(:update_profile,
    summary: "Set your division and birth year (only after opting in to leaderboards)",
    request_body: S.body(S.leaderboard_profile_request()),
    responses: [
      ok: {"Profile", "application/json", S.leaderboard_profile()},
      conflict: {"Not opted in to leaderboards", "application/json", S.error()},
      unprocessable_entity: {"Invalid values", "application/json", S.error()}
    ]
  )

  def update_profile(conn, _params) do
    with {:ok, profile} <-
           LeaderboardProfile.put(conn.assigns.tenant_context, body_params(conn)),
         do: json(conn, profile)
  end

  defp body_params(%Plug.Conn{body_params: %Plug.Conn.Unfetched{}}), do: %{}
  defp body_params(%Plug.Conn{body_params: params}), do: params
end

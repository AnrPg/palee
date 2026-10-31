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
  alias OpenApiSpex.{Parameter, Schema}

  action_fallback PaleeWeb.FallbackController

  tags(["Leaderboards"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  defp query(name, schema, description),
    do: %Parameter{
      name: name,
      in: :query,
      required: false,
      schema: schema,
      description: description
    }

  operation(:show,
    summary: "A WOD's leaderboard, filtered, with a percentile for each score",
    parameters: [
      %Parameter{
        name: :id,
        in: :path,
        required: true,
        schema: %Schema{type: :string, format: :uuid}
      },
      query(:division, %Schema{type: :string, enum: ~w(women men)}, "Only this division"),
      query(
        :age_group,
        %Schema{
          type: :string,
          enum: ~w(under_18 18_34 35_39 40_44 45_49 50_54 55_59 60_64 65_plus)
        },
        "Only this age group (age reached during the year)"
      ),
      query(:scale, %Schema{type: :string, maxLength: 64}, "Only this scale level slug"),
      query(:scope, %Schema{type: :string, enum: ~w(box branch)}, "Whole box or one branch"),
      query(:location_id, %Schema{type: :string, format: :uuid}, "The branch, with scope=branch"),
      query(
        :window,
        %Schema{type: :string, enum: ~w(day week month year all)},
        "Time window around `date` (default day)"
      ),
      query(:date, %Schema{type: :string, format: :date}, "Gym date (default today)"),
      query(:buddies, %Schema{type: :boolean}, "Only the viewer and their buddies")
    ],
    responses: [
      ok: {"Leaderboard", "application/json", S.workout_leaderboard()},
      not_found: {"No such WOD", "application/json", S.error()},
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

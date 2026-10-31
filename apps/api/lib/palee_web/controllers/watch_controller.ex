defmodule PaleeWeb.WatchController do
  @moduledoc "The watch companion's server side (ADR-375, CP-D8), called by the phone app."

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias OpenApiSpex.{Parameter, Schema}
  alias Palee.Application.WatchCompanion
  alias PaleeWeb.Schemas.Watch, as: S

  action_fallback PaleeWeb.FallbackController

  tags(["Watch"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  @id %Parameter{
    name: :id,
    in: :path,
    required: true,
    schema: %Schema{type: :string, format: :uuid}
  }
  @platform %Parameter{name: :platform, in: :path, required: true, schema: S.platform()}

  operation(:index,
    summary: "The person's paired watches and the contract version the server speaks",
    responses: [ok: {"Watches", "application/json", S.watches_response()}]
  )

  def index(conn, _params) do
    with {:ok, result} <- WatchCompanion.list(conn.assigns.user_context), do: json(conn, result)
  end

  operation(:pair,
    summary: "Pair a watch (or refresh its app version and settings)",
    parameters: [@platform],
    request_body: S.body(S.pair_request()),
    responses: [
      ok: {"The watch", "application/json", S.watch_response()},
      upgrade_required: {"The watch app is too old", "application/json", S.error()},
      unprocessable_entity: {"Invalid settings", "application/json", S.error()}
    ]
  )

  def pair(conn, %{platform: platform}) do
    with {:ok, watch} <-
           WatchCompanion.pair(conn.assigns.user_context, platform, conn.body_params),
         do: json(conn, %{watch: watch})
  end

  operation(:unpair,
    summary: "Unpair a watch; heart rate already recorded stays with its workouts",
    parameters: [@platform],
    responses: [
      no_content: "Unpaired",
      not_found: {"No such watch", "application/json", S.error()}
    ]
  )

  def unpair(conn, %{platform: platform}) do
    with :ok <- WatchCompanion.unpair(conn.assigns.user_context, platform),
         do: send_resp(conn, :no_content, "")
  end

  operation(:plan,
    summary: "What the watch runs for this execution: segments, progress and the pace line",
    parameters: [
      @id,
      %Parameter{name: :platform, in: :query, required: false, schema: S.platform()}
    ],
    responses: [
      ok: {"Watch plan", "application/json", S.plan_response()},
      not_found: {"Not your execution", "application/json", S.error()}
    ]
  )

  def plan(conn, %{id: id} = params) do
    with {:ok, plan} <-
           WatchCompanion.plan(conn.assigns.user_context, id, Map.get(params, :platform)),
         do: json(conn, %{plan: plan})
  end

  operation(:heart_rate,
    summary: "Numbered heart-rate batches from the watch; a resent batch is stored once",
    parameters: [@id],
    request_body: S.body(S.heart_rate_request()),
    responses: [
      ok: {"Stored", "application/json", S.heart_rate_stored()},
      forbidden: {"Health-data consent needed", "application/json", S.error()},
      not_found: {"Not your execution", "application/json", S.error()},
      unprocessable_entity: {"Invalid batch", "application/json", S.error()}
    ]
  )

  def heart_rate(conn, %{id: id}) do
    with {:ok, result} <-
           WatchCompanion.record_heart_rate(conn.assigns.user_context, id, conn.body_params),
         do: json(conn, result)
  end

  operation(:heart_rate_summary,
    summary: "Heart rate of this execution: average, highest, per section and zones",
    parameters: [@id],
    responses: [
      ok: {"Summary", "application/json", S.heart_rate_summary_response()},
      not_found: {"Not your execution", "application/json", S.error()}
    ]
  )

  def heart_rate_summary(conn, %{id: id}) do
    with {:ok, summary} <- WatchCompanion.heart_rate_summary(conn.assigns.user_context, id),
         do: json(conn, %{heart_rate: summary})
  end
end

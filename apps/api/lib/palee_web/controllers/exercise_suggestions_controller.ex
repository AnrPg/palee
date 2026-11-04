defmodule PaleeWeb.ExerciseSuggestionsController do
  @moduledoc "Suggestions for an exercise name being typed (ADR-461)."

  use PaleeWeb, :controller
  use PaleeWeb.ControllerSpecs

  alias Palee.Application.SuggestExerciseNames
  alias PaleeWeb.Schemas.ExerciseSuggestions, as: S

  action_fallback PaleeWeb.FallbackController

  tags(["Exercises"])
  security([%{"bearerAuth" => []}])

  operation(:index,
    summary: "Exercise-name suggestions: your own, your box's, Palee's",
    parameters: S.parameters(),
    responses: [ok: {"Exercise suggestions", "application/json", S.response()}]
  )

  def index(conn, params) do
    with {:ok, result} <- SuggestExerciseNames.call(conn.assigns.user_context, params),
         do: json(conn, result)
  end
end

defmodule Palee.Application.GetWorkoutDslManual do
  @moduledoc false

  alias Palee.Workouts

  # ADR-461: the vocabulary's exercise catalog includes the approved additions.
  def call, do: {:ok, Workouts.dsl_manual_with_additions()}
end

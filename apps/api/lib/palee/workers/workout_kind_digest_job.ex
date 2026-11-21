defmodule Palee.Workers.WorkoutKindDigestJob do
  @moduledoc """
  ADR-690, daily: the Palee team gets one email with the workout type names
  boxes added (and the disciplines they suggested) since the last one. No
  email on a day without news.
  """

  use Oban.Worker, queue: :default, max_attempts: 3, unique: [period: 3_600]

  require Logger

  alias Palee.Application.WorkoutKinds

  @impl Oban.Worker
  def perform(_job) do
    result = WorkoutKinds.send_digest()
    Logger.info("workout_kind_digest #{inspect(result)}")
    :ok
  end
end

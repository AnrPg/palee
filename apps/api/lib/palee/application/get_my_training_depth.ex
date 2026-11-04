defmodule Palee.Application.GetMyTrainingDepth do
  @moduledoc """
  `GET /api/me/progress/depth` (ADR-165): the member's own muscle coverage
  summary, qualities radar and training load across every provider, for the
  fixed Πρόοδος slots. Takes the Πρόοδος filter (`range`, `sources`; the
  exercise filter does not narrow these sections). Account-level and
  ungated like the account Πρόοδος: it is the member's own data.
  """

  alias Palee.Analytics
  alias Palee.Application.TrainingDepth

  def call(context, params, today \\ Date.utc_today()) do
    with {:ok, filter} <- Analytics.parse_progress_filter(Map.take(params, ["range", "sources"])) do
      # ADR-462 §5: the member's own resets; a coach's view never passes them.
      baselines = Analytics.metric_baselines(context, :member)

      sections = %{
        coverage: baselines["progress.depth.coverage"],
        qualities: baselines["progress.depth.qualities"],
        load: baselines["progress.depth.load"]
      }

      {:ok,
       context
       |> TrainingDepth.build(filter.range, today, sources: filter.sources, baselines: sections)
       |> Map.put(:sources, filter.sources)
       |> Map.put(:metric_baselines, iso_baselines(baselines))}
    end
  end

  defp iso_baselines(baselines),
    do: Map.new(baselines, fn {key, at} -> {key, DateTime.to_iso8601(at)} end)
end

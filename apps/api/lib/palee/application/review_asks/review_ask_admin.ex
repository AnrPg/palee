defmodule Palee.Application.ReviewAsks.ReviewAskAdmin do
  @moduledoc """
  ADR-355: staff set the Google Place ID and the milestones, and see counts
  only (no per-member list, so nobody is chased for a review).
  """

  alias Palee.ReviewAsks

  @summary_days 90

  def settings(context), do: {:ok, %{settings: present(ReviewAsks.settings(context))}}

  def update(context, params) do
    params = Map.new(params || %{}, fn {key, value} -> {to_string(key), value} end)

    case ReviewAsks.update_settings(context, params, Map.get(context, :user_id)) do
      {:ok, settings} -> {:ok, %{settings: present(settings)}}
      error -> error
    end
  end

  def summary(context) do
    since = DateTime.add(ReviewAsks.clock().now(), -@summary_days * 86_400, :second)
    {:ok, %{days: @summary_days, counts: ReviewAsks.summary(context, since)}}
  end

  defp present(settings) do
    settings
    |> Map.take([:google_place_id, :enabled, :milestones, :lock_version])
    |> Map.put(:google_review_url, ReviewAsks.write_review_url(settings.google_place_id))
  end
end

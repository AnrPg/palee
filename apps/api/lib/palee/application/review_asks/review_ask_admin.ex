defmodule Palee.Application.ReviewAsks.ReviewAskAdmin do
  @moduledoc """
  ADR-355: staff set the Google Place ID and the milestones, and see counts
  only (no per-member list, so nobody is chased for a review).

  ADR-387: the box finds its listing by name through the Places API (the
  Place ID stays as the fallback); a new Place ID is read at once, then
  daily by `Palee.Workers.GooglePlacesJob`.
  """

  require Logger

  alias Palee.Application.ReviewAsks.BoxReviews
  alias Palee.ReviewAsks

  @summary_days 90

  def settings(context) do
    settings = ReviewAsks.settings(context)

    {:ok,
     %{settings: present(settings), google: BoxReviews.google(context, settings.google_place_id)}}
  end

  def update(context, params) do
    params = Map.new(params || %{}, fn {key, value} -> {to_string(key), value} end)
    before = ReviewAsks.settings(context).google_place_id

    case ReviewAsks.update_settings(context, params, Map.get(context, :user_id)) do
      {:ok, settings} ->
        place_id = settings.google_place_id
        if place_id && place_id != before, do: refresh(context, place_id)
        {:ok, %{settings: present(settings), google: BoxReviews.google(context, place_id)}}

      error ->
        error
    end
  end

  @doc "«Βρες το box σου στο Google»: listings matching a name (ADR-387)."
  def search_places(%{organization_id: organization_id}, query) do
    with {:ok, query} <- ReviewAsks.place_query(query) do
      case ReviewAsks.places().search(query, language: BoxReviews.box_language(organization_id)) do
        {:ok, places} -> {:ok, %{places: Enum.map(places, &place/1)}}
        {:error, _reason} -> {:error, :places_unavailable}
      end
    end
  end

  defp place(place) do
    %{
      place_id: place.place_id,
      name: Map.get(place, :name),
      address: Map.get(place, :address),
      rating: Map.get(place, :rating),
      rating_count: Map.get(place, :rating_count)
    }
  end

  @doc "Reads the box's Google listing now (also the daily job's step)."
  def refresh(%{organization_id: organization_id} = context, place_id) do
    language = BoxReviews.box_language(organization_id)
    ReviewAsks.refresh_place(context, place_id, language, ReviewAsks.clock().now())
  rescue
    error ->
      Logger.warning("google place refresh failed: #{Exception.message(error)}")
      {:error, :places_unavailable}
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

defmodule Palee.ReviewAsks.Domain.GooglePlacePolicy do
  @moduledoc """
  ADR-387: the box's Google rating and reviews, read from the Places API and
  kept as a snapshot refreshed once a day.

    * At most #{5} reviews are kept: what Google returns, in Google's order,
      never chosen by Palee (no gating, ADR-355).
    * Each review keeps its author attribution (name, profile link, photo)
      and Google's own relative time, as Google's attribution rules ask; the
      site and app show «Από το Google» next to them.
    * A snapshot older than #{7} days is not shown (the refresh failed for a
      week); the rating then waits for the next good read.
    * Failures back off from 1 hour to the daily refresh.

  Pure: callers bring the read and the time.
  """

  @max_reviews 5
  @max_text 1_500
  @refresh_hours 24
  @stale_days 7
  @min_query 3
  @max_query 120

  def max_reviews, do: @max_reviews

  @doc "Validates a search text: `{:ok, query}` or `{:error, :invalid_place_query}`."
  def query(value) when is_binary(value) do
    value = String.trim(value)
    length = String.length(value)

    if length >= @min_query and length <= @max_query,
      do: {:ok, value},
      else: {:error, :invalid_place_query}
  end

  def query(_value), do: {:error, :invalid_place_query}

  @doc "The snapshot fields of a good read at `now`."
  def snapshot(place_id, details, now) do
    %{
      place_id: place_id,
      name: clip(details[:name], 200),
      rating: rating(details[:rating]),
      rating_count: count(details[:rating_count]),
      maps_uri: uri(details[:maps_uri]),
      reviews: details |> Map.get(:reviews, []) |> Enum.take(@max_reviews) |> Enum.map(&review/1),
      status: "ok",
      attempts: 0,
      fetched_at: now,
      next_refresh_at: DateTime.add(now, @refresh_hours * 3_600, :second)
    }
  end

  @doc "The snapshot fields after a failed read (`:not_found` empties it)."
  def failure(place_id, :not_found, _attempts, now) do
    %{
      place_id: place_id,
      name: nil,
      rating: nil,
      rating_count: nil,
      maps_uri: nil,
      reviews: [],
      status: "not_found",
      attempts: 0,
      fetched_at: now,
      next_refresh_at: DateTime.add(now, @refresh_hours * 3_600, :second)
    }
  end

  def failure(place_id, _reason, attempts, now) do
    attempts = attempts + 1
    hours = min(Integer.pow(2, attempts - 1), @refresh_hours)

    %{
      place_id: place_id,
      status: "failed",
      attempts: attempts,
      next_refresh_at: DateTime.add(now, hours * 3_600, :second)
    }
  end

  @doc """
  The snapshot to show for `place_id`, or nil: none, another place, not
  found, or older than #{@stale_days} days.
  """
  def visible(nil, _place_id, _now), do: nil
  def visible(_snapshot, nil, _now), do: nil

  def visible(%{place_id: place_id} = snapshot, place_id, now) do
    fresh = DateTime.diff(now, snapshot.fetched_at, :second) <= @stale_days * 86_400

    if fresh and snapshot.status != "not_found" and not is_nil(snapshot.rating),
      do: snapshot,
      else: nil
  end

  def visible(_snapshot, _place_id, _now), do: nil

  defp review(review) do
    %{
      "author_name" => clip(review[:author_name], 80),
      "author_uri" => uri(review[:author_uri]),
      "author_photo_uri" => uri(review[:author_photo_uri]),
      "rating" => review |> Map.get(:rating) |> star(),
      "text" => clip(review[:text], @max_text),
      "relative_time" => clip(review[:relative_time], 60),
      "published_at" => clip(review[:published_at], 40)
    }
  end

  defp rating(value) when is_number(value) and value >= 1 and value <= 5,
    do: Decimal.from_float(value * 1.0) |> Decimal.round(1)

  defp rating(_value), do: nil

  defp star(value) when is_integer(value) and value in 1..5, do: value
  defp star(value) when is_float(value), do: value |> round() |> max(1) |> min(5)
  defp star(_value), do: nil

  defp count(value) when is_integer(value) and value >= 0, do: value
  defp count(_value), do: nil

  defp clip(value, max) when is_binary(value), do: String.slice(value, 0, max)
  defp clip(_value, _max), do: nil

  defp uri("https://" <> _rest = value) when byte_size(value) <= 500, do: value
  defp uri(_value), do: nil
end

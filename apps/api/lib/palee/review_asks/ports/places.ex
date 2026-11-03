defmodule Palee.ReviewAsks.Ports.Places do
  @moduledoc """
  ADR-387: Google's listing of a box, behind a port. The real adapter calls
  the Places API with Palee's own server key (from config, never shown or
  logged); dev and test use a sandbox.

  Both callbacks answer normalised maps (string values, no raw JSON):

    * `search/2` – `[%{place_id, name, address, rating, rating_count}]`;
    * `details/2` – `%{place_id, name, rating, rating_count, maps_uri,
      reviews: [%{author_name, author_uri, author_photo_uri, rating, text,
      relative_time, published_at}]}`.

  `opts`: `language` (the box's language for Google's texts).
  """

  @type place :: %{required(:place_id) => String.t(), optional(atom()) => term()}

  @callback search(query :: String.t(), opts :: keyword()) ::
              {:ok, [place()]} | {:error, :places_unavailable | term()}
  @callback details(place_id :: String.t(), opts :: keyword()) ::
              {:ok, place()} | {:error, :not_found | :places_unavailable | term()}
end

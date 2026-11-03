defmodule Palee.Infrastructure.ReviewAsks.GooglePlaces do
  @moduledoc """
  ADR-387: the Places API (New) with Palee's own server key.

    * `search/2`: `POST places:searchText`, field mask limited to the id,
      name, address and rating (Text Search Pro fields).
    * `details/2`: `GET places/<id>`, field mask limited to the name,
      rating, rating count, Maps link and reviews.

  The key comes from `config :palee, :google_places_api, api_key: ...`
  (`GOOGLE_PLACES_API_KEY`) and travels only in the `X-Goog-Api-Key`
  header: never in a URL, a log or a response. Without a key every call
  answers `{:error, :places_unavailable}`.
  """

  @behaviour Palee.ReviewAsks.Ports.Places

  @base "https://places.googleapis.com/v1"
  @search_mask "places.id,places.displayName,places.formattedAddress,places.rating,places.userRatingCount"
  # No `reviews`: their texts and authors are not read (ADR-387 amendment).
  @details_mask "id,displayName,rating,userRatingCount,googleMapsUri"
  @place_id ~r/^[A-Za-z0-9_-]{10,300}$/

  @impl true
  def search(query, opts) do
    body = %{textQuery: query, languageCode: Keyword.get(opts, :language, "el"), pageSize: 5}

    case request(:post, "#{@base}/places:searchText", @search_mask, json: body) do
      {:ok, %{"places" => places}} when is_list(places) -> {:ok, Enum.map(places, &place/1)}
      {:ok, _empty} -> {:ok, []}
      error -> error
    end
  end

  @impl true
  def details(place_id, opts) do
    if Regex.match?(@place_id, place_id) do
      language = Keyword.get(opts, :language, "el")

      case request(:get, "#{@base}/places/#{place_id}", @details_mask,
             params: [languageCode: language]
           ) do
        {:ok, %{} = body} -> {:ok, details(body)}
        error -> error
      end
    else
      {:error, :not_found}
    end
  end

  defp request(method, url, mask, extra) do
    config = Application.get_env(:palee, :google_places_api, [])

    case Keyword.get(config, :api_key) do
      key when is_binary(key) and key != "" ->
        [
          method: method,
          url: url,
          headers: [{"x-goog-api-key", key}, {"x-goog-fieldmask", mask}],
          receive_timeout: 10_000,
          retry: false
        ]
        |> Keyword.merge(extra)
        |> Keyword.merge(Keyword.get(config, :req_options, []))
        |> Req.request()
        |> answer()

      _missing ->
        {:error, :places_unavailable}
    end
  end

  defp answer({:ok, %Req.Response{status: status, body: body}}) when status in 200..299,
    do: {:ok, body}

  defp answer({:ok, %Req.Response{status: status}}) when status in [400, 404],
    do: {:error, :not_found}

  defp answer({:ok, %Req.Response{status: status}}), do: {:error, {:http, status}}
  defp answer({:error, _exception}), do: {:error, :places_unavailable}

  defp place(place) do
    %{
      place_id: place["id"],
      name: get_in(place, ["displayName", "text"]),
      address: place["formattedAddress"],
      rating: place["rating"],
      rating_count: place["userRatingCount"]
    }
  end

  defp details(body) do
    %{
      place_id: body["id"],
      name: get_in(body, ["displayName", "text"]),
      rating: body["rating"],
      rating_count: body["userRatingCount"],
      maps_uri: body["googleMapsUri"]
    }
  end
end

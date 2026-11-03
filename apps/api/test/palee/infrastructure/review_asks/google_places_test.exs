defmodule Palee.Infrastructure.ReviewAsks.GooglePlacesTest do
  @moduledoc "ADR-387: the Places API adapter, against a Req.Test plug."

  use ExUnit.Case, async: false

  alias Palee.Infrastructure.ReviewAsks.GooglePlaces

  setup do
    previous = Application.get_env(:palee, :google_places_api)

    Application.put_env(
      :palee,
      :google_places_api,
      Keyword.put(previous || [], :api_key, "server-key")
    )

    on_exit(fn -> Application.put_env(:palee, :google_places_api, previous) end)
  end

  test "search sends the key in a header with a narrow field mask" do
    Req.Test.stub(Palee.GooglePlacesHttp, fn conn ->
      assert conn.method == "POST"
      assert conn.request_path == "/v1/places:searchText"
      assert ["server-key"] = Plug.Conn.get_req_header(conn, "x-goog-api-key")
      [mask] = Plug.Conn.get_req_header(conn, "x-goog-fieldmask")
      refute mask =~ "reviews"
      refute conn.query_string =~ "server-key"

      Req.Test.json(conn, %{
        "places" => [
          %{
            "id" => "ChIJabcdefghij",
            "displayName" => %{"text" => "Box Κυψέλη"},
            "formattedAddress" => "Φωκίωνος Νέγρη 12",
            "rating" => 4.8,
            "userRatingCount" => 126
          }
        ]
      })
    end)

    assert {:ok, [%{place_id: "ChIJabcdefghij", name: "Box Κυψέλη", rating_count: 126}]} =
             GooglePlaces.search("Box Κυψέλη", language: "el")
  end

  test "details normalise reviews; 404 is not found; no key means unavailable" do
    Req.Test.stub(Palee.GooglePlacesHttp, fn conn ->
      case conn.request_path do
        "/v1/places/ChIJabcdefghij" ->
          Req.Test.json(conn, %{
            "id" => "ChIJabcdefghij",
            "rating" => 4.7,
            "userRatingCount" => 10,
            "googleMapsUri" => "https://maps.google.com/?cid=1",
            "reviews" => [
              %{
                "rating" => 5,
                "text" => %{"text" => "Τέλειο"},
                "relativePublishTimeDescription" => "πριν από μία εβδομάδα",
                "authorAttribution" => %{"displayName" => "Νίκος", "uri" => "https://g/1"}
              }
            ]
          })

        _other ->
          conn |> Plug.Conn.put_status(404) |> Req.Test.json(%{})
      end
    end)

    assert {:ok, %{rating: 4.7, reviews: [%{author_name: "Νίκος", text: "Τέλειο", rating: 5}]}} =
             GooglePlaces.details("ChIJabcdefghij", language: "el")

    assert {:error, :not_found} = GooglePlaces.details("ChIJzzzzzzzzzz", [])
    assert {:error, :not_found} = GooglePlaces.details("../etc", [])

    Application.put_env(:palee, :google_places_api,
      req_options: [plug: {Req.Test, Palee.GooglePlacesHttp}]
    )

    assert {:error, :places_unavailable} = GooglePlaces.search("Box", [])
  end
end

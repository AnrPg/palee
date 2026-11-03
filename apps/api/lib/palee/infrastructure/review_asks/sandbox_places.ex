defmodule Palee.Infrastructure.ReviewAsks.SandboxPlaces do
  @moduledoc """
  ADR-387: a Places API stand-in for dev and test. A search returns one
  listing named after the query; Place IDs starting with `missing` are not
  found and those starting with `down` fail.
  """

  @behaviour Palee.ReviewAsks.Ports.Places

  @impl true
  def search(query, _opts) do
    {:ok,
     [
       %{
         place_id: "ChIJsandbox" <> String.slice(Base.encode16(query), 0, 12),
         name: query,
         address: "Φωκίωνος Νέγρη 12, Αθήνα",
         rating: 4.8,
         rating_count: 126
       }
     ]}
  end

  @impl true
  def details("missing" <> _rest, _opts), do: {:error, :not_found}
  def details("down" <> _rest, _opts), do: {:error, :places_unavailable}

  def details(place_id, _opts) do
    {:ok,
     %{
       place_id: place_id,
       name: "Box (sandbox)",
       rating: 4.8,
       rating_count: 126,
       maps_uri: "https://maps.google.com/?cid=1",
       reviews: [
         %{
           author_name: "Μαρία Π.",
           author_uri: "https://www.google.com/maps/contrib/1",
           author_photo_uri: nil,
           rating: 5,
           text: "Υπέροχοι coaches.",
           relative_time: "πριν από 2 μήνες",
           published_at: "2026-09-01T10:00:00Z"
         }
       ]
     }}
  end
end

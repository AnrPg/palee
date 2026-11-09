defmodule Palee.Places do
  @moduledoc """
  Places context (ADR-141, ADR-154): the neighbourhood gazetteer, a
  person's «Η περιοχή μου», and Γύρω μου discovery: the filter, where a
  search starts, what it asks of each kind, and the cross-gym search.
  """

  alias Palee.Places.{DiscoveryStore, GazetteerStore, HomeAreaStore}

  alias Palee.Places.Domain.{
    AlertPolicy,
    AroundFilter,
    AroundPlan,
    Cursor,
    Origin,
    SearchArea,
    SearchKey,
    WorldPlace,
    GeonamesPlace
  }

  # The filter.
  defdelegate parse_filter(params, vocabulary), to: AroundFilter, as: :parse
  defdelegate filter_params(filter), to: AroundFilter, as: :to_params
  defdelegate active_filters(filter), to: AroundFilter, as: :active_count
  defdelegate kinds(), to: AroundFilter
  defdelegate filter_version(), to: AroundFilter, as: :version
  defdelegate filter_whens(), to: AroundFilter, as: :whens
  defdelegate filter_times(), to: AroundFilter, as: :times
  defdelegate filter_costs(), to: AroundFilter, as: :costs
  defdelegate origin_types(), to: Origin, as: :types
  defdelegate max_neighbourhoods(), to: AroundFilter

  # Where a search starts and where it looks.
  defdelegate parse_origin(spec), to: Origin, as: :parse_request
  defdelegate resolve_origin(candidates), to: Origin, as: :resolve
  defdelegate places_origin(type, places), to: Origin, as: :from_places
  defdelegate point_origin(type, point, label), to: Origin, as: :from_point
  defdelegate present_origin(origin), to: Origin, as: :present
  defdelegate round_point(latitude, longitude), to: SearchArea
  defdelegate circle(points, radius_m), to: SearchArea
  defdelegate viewport(bbox), to: SearchArea
  defdelegate distance_km(metres), to: SearchArea
  defdelegate wider_radii_km(radius_km), to: SearchArea
  defdelegate fallback_radii_km(radius_km), to: SearchArea
  defdelegate thin?(total), to: SearchArea

  # What the filter asks of each kind.
  defdelegate plan(filter, viewer, now, purpose), to: AroundPlan, as: :build
  defdelegate created_after(plan, since), to: AroundPlan
  defdelegate section_limit(limit), to: AroundPlan
  defdelegate page_limit(limit), to: AroundPlan
  defdelegate pins_limit(), to: AroundPlan
  defdelegate encode_cursor(kind, row), to: Cursor, as: :encode
  defdelegate decode_cursor(kind, token), to: Cursor, as: :decode

  # Alerts.
  defdelegate alert_day(now), to: AlertPolicy, as: :day
  defdelegate alert_due?(checked_on, day), to: AlertPolicy, as: :due?
  defdelegate notify_alert?(total), to: AlertPolicy, as: :notify?
  defdelegate alert_dedupe_key(filter_id, day), to: AlertPolicy, as: :dedupe_key

  # The gazetteer.
  @doc "Gazetteer places matching `query` (case and accents ignored)."
  def search_neighbourhoods(query, limit \\ 20) do
    case SearchKey.normalize(query) do
      "" -> []
      normalized -> GazetteerStore.search(normalized, limit)
    end
  end

  @doc "Gazetteer places by id, in the order asked."
  def neighbourhoods([]), do: []

  def neighbourhoods(ids) do
    by_id = ids |> GazetteerStore.get_many() |> Map.new(&{&1.id, &1})
    ids |> Enum.map(&Map.get(by_id, &1)) |> Enum.reject(&is_nil/1)
  end

  defdelegate nearest_neighbourhood(point), to: GazetteerStore, as: :nearest

  @doc """
  The towns an origin lies in (ADR-583), as the names a location's town is
  matched by (Greek and English): each origin place's town (itself when it
  is a city or town, else its city by slug, else the town around it); for a
  point, the town around it. Empty when the gazetteer knows none.
  """
  def origin_towns(%{neighbourhood_ids: ids, points: points}) do
    towns =
      case neighbourhoods(ids) do
        [] -> Enum.map(points, &GazetteerStore.town_at/1)
        places -> towns_of(places)
      end

    towns
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(& &1.id)
    |> Enum.flat_map(&[&1.name, &1[:name_en]])
    |> Enum.reject(&(is_nil(&1) or String.trim(&1) == ""))
    |> Enum.uniq()
  end

  defp towns_of(places) do
    by_slug =
      places
      |> Enum.map(& &1[:city_slug])
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> GazetteerStore.get_by_slugs()
      |> Map.new(&{&1.slug, &1})

    Enum.map(places, fn
      %{kind: "city"} = place -> place
      place -> Map.get(by_slug, place[:city_slug]) || town_around(place)
    end)
  end

  defp town_around(%{latitude: latitude, longitude: longitude})
       when is_number(latitude) and is_number(longitude),
       do: GazetteerStore.town_at({latitude, longitude})

  defp town_around(_place), do: nil

  # The world beyond the curated gazetteer (ADR-188).
  defdelegate geocoder_layers(), to: WorldPlace, as: :layers
  defdelegate geocoder_area_layers(), to: WorldPlace, as: :area_layers
  defdelegate world_suggestions(local, english), to: WorldPlace, as: :suggestions
  defdelegate without_known_places(suggestions, known), to: WorldPlace, as: :without_duplicates
  defdelegate address_place?(place), to: WorldPlace, as: :address?
  defdelegate area_for_address(address, local, english), to: WorldPlace
  defdelegate world_place_id(slug), to: WorldPlace, as: :id

  # Towns worldwide from GeoNames (ADR-188).
  defdelegate geonames_place(line, admin1, countries), to: GeonamesPlace, as: :from_line
  defdelegate geonames_admin1_names(lines), to: GeonamesPlace, as: :admin1_names
  defdelegate geonames_country_names(lines), to: GeonamesPlace, as: :country_names
  defdelegate duplicates_known_place?(place, known), to: GeonamesPlace, as: :duplicate?
  defdelegate upsert_reference_places(source, places), to: GazetteerStore, as: :upsert_many
  defdelegate reference_refreshed_at(source), to: GazetteerStore, as: :refreshed_at
  defdelegate reference_places(source), to: GazetteerStore, as: :list_source

  @doc "Stores a geocoded place (or refreshes it) and returns the gazetteer row."
  def import_neighbourhood(place),
    do:
      GazetteerStore.import(
        Map.merge(place, %{
          search_key: WorldPlace.search_key(place),
          name_key: WorldPlace.name_key(place)
        })
      )

  # «Η περιοχή μου».
  defdelegate home_area(context), to: HomeAreaStore, as: :list
  defdelegate home_country(context), to: HomeAreaStore, as: :country
  defdelegate replace_home_area(context, ids, now), to: HomeAreaStore, as: :replace

  # Discovery.
  defdelegate search(context, kind, area, plan, cursor, limit), to: DiscoveryStore
  defdelegate search_town(context, kind, points, towns, plan, limit), to: DiscoveryStore
  defdelegate counts(context, area, plan, radii_m), to: DiscoveryStore
  defdelegate pins(context, area, plan, limit), to: DiscoveryStore
  defdelegate people_within(context, user_ids, radius_m), to: DiscoveryStore
end

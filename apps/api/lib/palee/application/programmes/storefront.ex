defmodule Palee.Application.Programmes.Storefront do
  @moduledoc """
  ADR-370: programmes as anyone sees them, without an account: the
  cross-business catalogue, a box's own programmes on its public page and
  one programme with its preview days and published reviews. Reads run in
  the seller's scope (`PublicBox.resolve/1`) and project public fields
  only; buyers are never shown, reviewers by first name only.
  """

  alias Palee.Application.Programmes.Presenter
  alias Palee.Application.PublicBox
  alias Palee.{Identity, Programmes}

  @max_query 60

  def catalogue(params) do
    filters = %{
      query: query(params[:query]),
      goal: if(params[:goal] in Programmes.goals(), do: params[:goal]),
      level: if(params[:level] in Programmes.levels(), do: params[:level]),
      limit: clamp(params[:limit], 1, 50, 20),
      offset: clamp(params[:offset], 0, 10_000, 0)
    }

    {:ok,
     %{programmes: Programmes.catalogue(filters), limit: filters.limit, offset: filters.offset}}
  end

  # LIKE wildcards in the visitor's text are matched literally.
  defp query(text) when is_binary(text) do
    case text |> String.trim() |> String.slice(0, @max_query) do
      "" ->
        nil

      clean ->
        clean
        |> String.replace("\\", "\\\\")
        |> String.replace("%", "\\%")
        |> String.replace("_", "\\_")
    end
  end

  defp query(_text), do: nil

  defp clamp(value, min, max, _default) when is_integer(value), do: value |> max(min) |> min(max)
  defp clamp(_value, _min, _max, default), do: default

  def box_programmes(slug) do
    with {:ok, box, context} <- PublicBox.resolve(slug) do
      programmes =
        context
        |> Programmes.list_programmes(%{statuses: ["published"]})
        |> Enum.filter(&Programmes.on_sale?/1)

      reviews = Programmes.review_summaries(context, Enum.map(programmes, & &1.id))

      {:ok,
       %{
         box: box,
         programmes:
           Enum.map(programmes, fn programme ->
             version = Programmes.get_version(context, programme.current_version_id)

             Presenter.public(programme, version, %{
               reviews: Map.get(reviews, programme.id, %{average: nil, count: 0})
             })
           end)
       }}
    end
  end

  def programme(slug, id) do
    with {:ok, box, context} <- PublicBox.resolve(slug),
         %{} = programme <- Programmes.get_programme(context, id) || {:error, :not_found},
         true <- Programmes.on_sale?(programme) || {:error, :not_found},
         %{} = version <-
           Programmes.get_version(context, programme.current_version_id) || {:error, :not_found} do
      reviews = Programmes.list_reviews(context, programme.id, %{published_only: true, limit: 20})
      names = first_names(reviews)

      {:ok,
       %{
         box: box,
         programme:
           Presenter.public(programme, version, %{
             preview:
               version.days
               |> Programmes.preview(programme.preview_days)
               |> Presenter.preview_days(),
             week_outline: week_outline(version),
             reviews:
               Map.get(Programmes.review_summaries(context, [programme.id]), programme.id, %{
                 average: nil,
                 count: 0
               }),
             latest_reviews: Enum.map(reviews, &Presenter.review(&1, Map.get(names, &1.user_id)))
           })
       }}
    end
  end

  # How many WODs each week has, without naming them.
  defp week_outline(version) do
    counts = Enum.frequencies_by(version.days, &(div(&1["day"], 7) + 1))
    Enum.map(1..version.weeks, &%{week: &1, sessions: Map.get(counts, &1, 0)})
  end

  defp first_names(reviews) do
    reviews
    |> Enum.map(& &1.user_id)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Identity.list_by_ids()
    |> Map.new(fn user -> {user.id, %{nickname: user.nickname}} end)
  end
end

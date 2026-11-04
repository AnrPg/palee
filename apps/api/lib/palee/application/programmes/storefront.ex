defmodule Palee.Application.Programmes.Storefront do
  @moduledoc """
  ADR-370: programmes as anyone sees them, without an account: the
  cross-business catalogue, a box's own programmes on its public page and
  one programme with its preview days and published reviews. Reads run in
  the seller's scope (`PublicBox.resolve/1`) and project public fields
  only; buyers are never shown, reviewers by first name only.
  """

  alias Palee.Application.Programmes.{Covers, Facts, Presenter}
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
     %{
       programmes: Enum.map(Programmes.catalogue(filters), &catalogue_row/1),
       limit: filters.limit,
       offset: filters.offset
     }}
  end

  # ADR-541/542: the cover's public URL and the facts shown, from the
  # projection's raw columns (which are not passed on).
  defp catalogue_row(row) do
    row
    |> Map.drop([:cover_object_key, :facts, :equipment_removed])
    |> Map.put(:cover_url, Covers.catalogue_url(row.organization_id, row[:cover_object_key]))
    |> Map.merge(Facts.shown(row, row[:facts]))
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
      {:ok, %{box: box, programmes: on_sale(context)}}
    end
  end

  @doc """
  The business's programmes on sale (newest first), as public cards: what
  its own page and its website (ADR-543) list. `limit` keeps the first ones.
  """
  def on_sale(context, limit \\ nil) do
    programmes =
      context
      |> Programmes.list_programmes(%{statuses: ["published"]})
      |> Enum.filter(&Programmes.on_sale?/1)
      |> Enum.sort_by(& &1.published_at, {:desc, DateTime})
      |> then(&if(limit, do: Enum.take(&1, limit), else: &1))

    reviews = Programmes.review_summaries(context, Enum.map(programmes, & &1.id))
    covers = Covers.urls(context, programmes)

    Enum.map(programmes, fn programme ->
      version = Programmes.get_version(context, programme.current_version_id)

      Presenter.public(
        programme,
        version,
        Map.merge(
          %{
            reviews: Map.get(reviews, programme.id, %{average: nil, count: 0}),
            cover_url: get_in(covers, [programme.id, :url])
          },
          Facts.shown(programme, Facts.of_version(context, version))
        )
      )
    end)
  end

  @doc "How many programmes the business has on sale (ADR-543)."
  def on_sale_count(context) do
    context
    |> Programmes.list_programmes(%{statuses: ["published"]})
    |> Enum.count(&Programmes.on_sale?/1)
  end

  def programme(slug, id) do
    with {:ok, box, context} <- PublicBox.resolve(slug),
         %{} = programme <- Programmes.get_programme(context, id) || {:error, :not_found},
         true <- Programmes.on_sale?(programme) || {:error, :not_found},
         %{} = version <-
           Programmes.get_version(context, programme.current_version_id) || {:error, :not_found} do
      reviews = Programmes.list_reviews(context, programme.id, %{published_only: true, limit: 20})
      names = first_names(reviews)
      cover = Covers.urls(context, [programme])[programme.id]
      facts = Facts.of_version(context, version)

      {:ok,
       %{
         box: box,
         programme:
           Presenter.public(programme, version, %{
             preview:
               version.days
               |> Programmes.preview(programme.preview_days)
               |> Presenter.preview_days(),
             week_outline: week_outline(version, programme.preview_days, facts),
             coach_name: coach_name(programme.author_id),
             reviews:
               Map.get(Programmes.review_summaries(context, [programme.id]), programme.id, %{
                 average: nil,
                 count: 0
               }),
             latest_reviews: Enum.map(reviews, &Presenter.review(&1, Map.get(names, &1.user_id))),
             cover_url: cover.url
           })
           |> Map.merge(Facts.shown(programme, facts))
       }}
    end
  end

  # How many WODs each week has and, for every day, whether it trains, its
  # workout type and its minutes (the mockup's «Ημ. 3 · Δύναμη · ~45′»),
  # never a WOD's title or content: locked days stay locked, and the preview
  # days show their WODs in `preview` as before.
  defp week_outline(version, preview_days, facts) do
    counts = Enum.frequencies_by(version.days, &(div(&1["day"], 7) + 1))
    outline = Map.new((facts || %{})["days"] || [], &{&1["day"], &1})
    preview_days = preview_days || 0

    Enum.map(1..version.weeks, fn week ->
      %{
        week: week,
        sessions: Map.get(counts, week, 0),
        days:
          Enum.map(0..6, fn weekday ->
            day = (week - 1) * 7 + weekday
            row = Map.get(outline, day)

            %{
              day: day,
              weekday: weekday,
              rest: is_nil(row),
              workout_type: row && row["type"],
              minutes: row && row["minutes"],
              preview: day < preview_days
            }
          end)
      }
    end)
  end

  # ADR-370 addendum: the author's public name under the title; nil once the
  # account is deleted (the row gone, or anonymised to a `deleted.` handle).
  defp coach_name(nil), do: nil

  defp coach_name(author_id) do
    case Identity.list_by_ids([author_id]) do
      [%{handle: "deleted." <> _rest}] -> nil
      [%{nickname: name}] when is_binary(name) and name != "" -> name
      _missing -> nil
    end
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

defmodule Palee.Application.ReviewAsks.BoxReviews do
  @moduledoc """
  ADR-386: the box's own reviews, in the app and on its website.

    * Members of the box read every review (newest first) with the average,
      and write or edit their own once they have checked in.
    * Staff read the same list and reply; nobody can delete someone else's
      review.
    * The Google rating and reviews (ADR-387) travel next to them, kept
      apart, with their own average.

  Authors show by first name only.
  """

  alias Palee.{Community, Identity, Organizations, ReviewAsks}

  @page 20
  @max_page 50
  @locale ~r/^[a-z]{2}(-[A-Za-z]{2,4})?$/

  @doc "The box's reviews for a member: list, stats, their own and whether they may write."
  def for_member(%{user_id: user_id} = context, params \\ %{}) do
    page = page(params)
    facts = ReviewAsks.signals().facts(context, user_id)
    mine = ReviewAsks.get_review(context, user_id)

    {:ok,
     context
     |> listing(page)
     |> Map.merge(%{
       mine: mine && present(mine, names([mine])),
       can_review: ReviewAsks.may_review(facts) == :ok
     })}
  end

  @doc "The box's reviews for staff, to read and reply."
  def for_staff(context, params \\ %{}), do: {:ok, listing(context, page(params))}

  @doc "Writes or edits the person's own review."
  def save_mine(%{user_id: user_id} = context, params) do
    params = stringify(params)
    facts = ReviewAsks.signals().facts(context, user_id)

    with :ok <- ReviewAsks.may_review(facts),
         {:ok, review} <-
           ReviewAsks.save_review(context, user_id, params, locale(params), now()) do
      {:ok, %{review: present(review, names([review]))}}
    end
  end

  @doc "The author deletes their own review."
  def delete_mine(%{user_id: user_id} = context) do
    :ok = ReviewAsks.delete_review(context, user_id)
    :ok
  end

  @doc "The box replies to a review (or edits its reply)."
  def reply(context, id, params) do
    with {:ok, review} <-
           ReviewAsks.reply_review(
             context,
             id,
             stringify(params),
             Map.get(context, :user_id),
             now()
           ) do
      {:ok, %{review: present(review, names([review]))}}
    end
  end

  @doc """
  What the website and the app show: the in-app reviews (stats and the
  latest few) and, apart, the Google listing when the box set its Place ID.
  """
  def public(context, place_id) do
    stats = ReviewAsks.review_stats(context)
    latest = ReviewAsks.list_reviews(context, %{limit: ReviewAsks.public_latest(), offset: 0})
    names = names(latest)

    %{
      palee: %{
        count: stats.count,
        average: stats.average,
        latest: Enum.map(latest, &present(&1, names))
      },
      google: google(context, place_id)
    }
  end

  @doc """
  The Google listing as shown: rating, number of reviews and links, or nil.
  No review texts until a lawyer has checked Google's terms (ADR-387
  amendment).
  """
  def google(_context, nil), do: nil

  def google(context, place_id) do
    case ReviewAsks.visible_place(context, place_id, now()) do
      nil ->
        nil

      snapshot ->
        %{
          name: snapshot.name,
          rating: snapshot.rating && Decimal.to_float(snapshot.rating),
          count: snapshot.rating_count,
          maps_uri: snapshot.maps_uri || ReviewAsks.read_reviews_url(place_id),
          write_review_url: ReviewAsks.write_review_url(place_id),
          fetched_at: snapshot.fetched_at
        }
    end
  end

  defp listing(context, page) do
    stats = ReviewAsks.review_stats(context)
    reviews = ReviewAsks.list_reviews(context, page)
    names = names(reviews)
    settings = ReviewAsks.settings(context)

    %{
      count: stats.count,
      average: stats.average,
      reviews: Enum.map(reviews, &present(&1, names)),
      has_more: length(reviews) == page.limit,
      google: google(context, settings.google_place_id)
    }
  end

  defp present(review, names) do
    %{
      id: review.id,
      rating: review.rating,
      body: review.body,
      author_name: Map.get(names, review.user_id),
      created_at: review.inserted_at,
      edited_at: review.edited_at,
      reply: review.reply_body && %{body: review.reply_body, replied_at: review.replied_at}
    }
  end

  # First names only; people who hide themselves (ADR-143) show without one.
  defp names(reviews) do
    ids = reviews |> Enum.map(& &1.user_id) |> Enum.uniq()
    hidden = ids |> Community.hidden_member_ids() |> MapSet.new()

    ids
    |> Enum.reject(&MapSet.member?(hidden, &1))
    |> Identity.list_by_ids()
    |> Map.new(&{&1.id, ReviewAsks.author_name(display_name(&1))})
  end

  defp display_name(user),
    do: Map.get(user, :display_name) || Map.get(user, :nickname) || Map.get(user, :handle)

  defp page(params) do
    params = stringify(params)
    limit = params |> Map.get("limit") |> integer(@page) |> min(@max_page) |> max(1)
    offset = params |> Map.get("offset") |> integer(0) |> max(0)
    %{limit: limit, offset: offset}
  end

  defp integer(value, _default) when is_integer(value), do: value

  defp integer(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} -> number
      _other -> default
    end
  end

  defp integer(_value, default), do: default

  defp locale(params) do
    case Map.get(params, "locale") do
      value when is_binary(value) -> if Regex.match?(@locale, value), do: value, else: nil
      _other -> nil
    end
  end

  @doc "The box's language (its default locale), for Google's texts."
  def box_language(organization_id) do
    case Organizations.get_organization_settings(organization_id) do
      %{default_locale: locale} when is_binary(locale) -> locale |> String.split("-") |> hd()
      _none -> "el"
    end
  end

  defp now, do: ReviewAsks.clock().now()

  defp stringify(params),
    do: Map.new(params || %{}, fn {key, value} -> {to_string(key), value} end)
end

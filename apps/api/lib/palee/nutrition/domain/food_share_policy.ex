defmodule Palee.Nutrition.Domain.FoodSharePolicy do
  @moduledoc """
  Sharing an own food with everyone (ADR-421 addendum). Only on the
  person's explicit choice, never by default, and only for a product
  barcode (not a shop's own code, not a food without one).

  What is shared is product data only: barcode, name, brand, portion and
  the six nutrients per 100 g. Never the person, a meal, a note or a photo.

    * Palee's public cache (`food_products`) gets a row with source
      `palee_members` when no public source already has the product: a
      product from Open Food Facts, USDA or a list is never overwritten, and
      the first share of a barcode wins.
    * The share is queued for Open Food Facts (`off_status: queued`); a
      failure is retried after 1, 5, 30 minutes, then hourly, up to 6
      attempts; a rejection is final. Open Food Facts already having the
      product ends it as `exists` (nothing is overwritten there either).
  """

  @source "palee_members"
  @max_attempts 6
  @claim_timeout_seconds 300
  @backoff_minutes [1, 5, 30, 60, 60, 60]
  @languages ~w(ar bg de el en es fr he it nl pt ru)

  def source, do: @source
  def claim_timeout_seconds, do: @claim_timeout_seconds

  @doc "Whether a barcode may be shared: a product barcode, not a shop's own code."
  def shareable_barcode?(barcode, in_store?), do: is_binary(barcode) and not in_store?

  @doc "The product language Open Food Facts gets: the person's language, two letters."
  def language(locale) when is_binary(locale) do
    short = locale |> String.split(["-", "_"]) |> hd() |> String.downcase()
    if short in @languages, do: short, else: "el"
  end

  def language(_locale), do: "el"

  @doc "The share row (audit and outbox) of an own food shared at `now`."
  def share_attrs(food, user_id, language, now) do
    %{
      barcode: food.barcode,
      user_id: user_id,
      name: food.name,
      brand: food.brand,
      serving_size: food.serving_label,
      portion_hint: food.portion_hint,
      nutrients: food.nutrients || %{},
      language: language,
      shared_at: now,
      off_status: "queued",
      off_attempts: 0,
      off_next_attempt_at: now,
      inserted_at: now,
      updated_at: now
    }
  end

  @doc "The public cache row of a shared product: found, from members, nothing personal."
  def cache_attrs(share, now) do
    %{
      barcode: share.barcode,
      status: "found",
      source: @source,
      name: share.name,
      brand: share.brand,
      quantity: nil,
      serving_size: share.serving_size,
      image_url: nil,
      categories: [],
      nutrients: share.nutrients,
      portion_hint: share.portion_hint,
      attribution: nil,
      attempts: 0,
      next_attempt_at: nil,
      claimed_at: nil,
      fetched_at: now,
      last_error: nil,
      inserted_at: now,
      updated_at: now
    }
  end

  @doc "The share's outbox changes after a contribution outcome at `now`."
  def after_contribution(:ok, _share, now),
    do: done("sent") |> Map.put(:off_sent_at, now)

  def after_contribution({:error, :exists}, _share, _now), do: done("exists")

  def after_contribution({:error, {:rejected, reason}}, _share, _now),
    do: done("failed") |> Map.put(:off_last_error, describe(reason))

  def after_contribution({:error, reason}, share, now) do
    attempts = share.off_attempts || 1

    if attempts >= @max_attempts do
      done("failed") |> Map.put(:off_last_error, describe(reason))
    else
      minutes = Enum.at(@backoff_minutes, attempts - 1, 60)

      %{
        off_status: "queued",
        off_next_attempt_at: DateTime.add(now, minutes * 60, :second),
        off_claimed_at: nil,
        off_last_error: describe(reason)
      }
    end
  end

  defp done(status),
    do: %{
      off_status: status,
      off_next_attempt_at: nil,
      off_claimed_at: nil,
      off_last_error: nil
    }

  defp describe(reason), do: reason |> inspect() |> String.slice(0, 200)
end

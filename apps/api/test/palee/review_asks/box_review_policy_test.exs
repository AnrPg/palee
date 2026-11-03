defmodule Palee.ReviewAsks.BoxReviewPolicyTest do
  @moduledoc "ADR-386/387: in-app reviews and the Google snapshot, pure rules."

  use ExUnit.Case, async: true

  alias Palee.ReviewAsks.Domain.{BoxReviewPolicy, GooglePlacePolicy}

  @now ~U[2026-11-02 10:00:00.000000Z]

  test "only people who checked in may review" do
    assert :ok = BoxReviewPolicy.may_review(%{attendance_count: 1})
    assert {:error, :review_needs_check_in} = BoxReviewPolicy.may_review(%{attendance_count: 0})
    assert {:error, :review_needs_check_in} = BoxReviewPolicy.may_review(%{})
  end

  test "a review: 1–5 stars and an optional, trimmed text" do
    assert {:ok, %{rating: 5, body: nil}} =
             BoxReviewPolicy.review(%{"rating" => 5, "body" => "  "})

    assert {:ok, %{rating: 1, body: "Όχι"}} =
             BoxReviewPolicy.review(%{"rating" => 1, "body" => " Όχι "})

    assert {:error, {:invalid_fields, %{rating: "invalid"}}} =
             BoxReviewPolicy.review(%{"rating" => 0})

    assert {:error, {:invalid_fields, %{body: "too_long"}}} =
             BoxReviewPolicy.review(%{"rating" => 3, "body" => String.duplicate("a", 2001)})

    assert {:ok, "Ευχαριστούμε"} = BoxReviewPolicy.reply(%{"body" => " Ευχαριστούμε "})

    assert {:error, {:invalid_fields, %{body: "invalid"}}} =
             BoxReviewPolicy.reply(%{"body" => " "})
  end

  test "average and first names" do
    assert BoxReviewPolicy.average(%{count: 0, sum: 0}) == nil
    assert BoxReviewPolicy.average(%{count: 3, sum: 13}) == 4.3
    assert BoxReviewPolicy.author_name("Ελένη Παπαδοπούλου") == "Ελένη"
    assert BoxReviewPolicy.author_name("  ") == nil
    assert BoxReviewPolicy.author_name(nil) == nil
  end

  test "a Google read keeps the rating and count, never review texts; refreshed daily" do
    reviews =
      for n <- 1..7, do: %{author_name: "A#{n}", author_uri: "http://x", rating: 4.6, text: "t"}

    snapshot =
      GooglePlacePolicy.snapshot(
        "ChIJplace12345",
        %{name: "Box", rating: 4.84, rating_count: 9, reviews: reviews},
        @now
      )

    # ADR-387 amendment: no review texts or authors until a legal check.
    refute Map.has_key?(snapshot, :reviews)
    assert snapshot.rating_count == 9
    assert Decimal.equal?(snapshot.rating, Decimal.new("4.8"))
    assert snapshot.next_refresh_at == DateTime.add(@now, 86_400, :second)
  end

  test "failures back off and stale or other-place snapshots are not shown" do
    assert %{status: "failed", attempts: 1, next_refresh_at: next} =
             GooglePlacePolicy.failure("p", :places_unavailable, 0, @now)

    assert next == DateTime.add(@now, 3_600, :second)

    assert %{attempts: 6, next_refresh_at: later} =
             GooglePlacePolicy.failure("p", :places_unavailable, 5, @now)

    assert later == DateTime.add(@now, 24 * 3_600, :second)

    assert %{status: "not_found", rating: nil} =
             GooglePlacePolicy.failure("p", :not_found, 2, @now)

    good = %{place_id: "p", status: "ok", rating: Decimal.new("4.5"), fetched_at: @now}
    assert GooglePlacePolicy.visible(good, "p", @now) == good
    refute GooglePlacePolicy.visible(good, "other", @now)
    refute GooglePlacePolicy.visible(good, nil, @now)

    refute GooglePlacePolicy.visible(
             %{good | fetched_at: DateTime.add(@now, -8 * 86_400)},
             "p",
             @now
           )

    assert {:error, :invalid_place_query} = GooglePlacePolicy.query("ab")
    assert {:ok, "Box Κυψέλη"} = GooglePlacePolicy.query(" Box Κυψέλη ")
  end
end

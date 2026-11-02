defmodule PaleeWeb.BoxReviewsControllerTest do
  @moduledoc """
  ADR-386/387 as the RLS runtime role: a member who checked in writes one
  review, edits it, deletes it; staff reply but cannot delete; the Google
  listing is found by name and shown apart; the website shows both.
  """

  use PaleeWeb.ConnCase, async: false

  import Palee.TestFixtures

  alias Palee.Application.{PublishBoxPublicProfile, UpdateBoxPublicProfile}
  alias Palee.Organizations

  setup do
    previous = Application.get_env(:palee, :review_signals)
    Application.put_env(:palee, :review_signals, Palee.TestSupport.FakeReviewSignals)

    on_exit(fn ->
      Application.put_env(:palee, :review_signals, previous)
      Application.delete_env(:palee, :fake_review_signals)
    end)

    owner = admin_fixture()
    member =
      user_fixture(%{
        nickname: "eleni_#{System.unique_integer([:positive])}",
        display_name: "Ελένη Παπαδοπούλου"
      })
    newcomer = user_fixture()

    {:ok, organization} =
      Organizations.create_organization(%{name: "Review Box #{System.unique_integer([:positive])}"})

    for {user, role} <- [{owner, :owner}, {member, :member}, {newcomer, :member}] do
      {:ok, _membership} =
        Organizations.add_membership(%{
          organization_id: organization.id,
          user_id: user.id,
          role: role,
          status: :active,
          joined_at: DateTime.utc_now()
        })
    end

    {:ok, context} = Organizations.resolve_tenant_context(owner, organization.slug)

    {:ok, profile} =
      UpdateBoxPublicProfile.call(context, %{"about" => "Box", "disciplines" => ["crossfit"]})

    {:ok, _profile} =
      PublishBoxPublicProfile.publish(context, %{"lock_version" => profile.lock_version})

    %{
      owner: owner,
      member: member,
      newcomer: newcomer,
      organization: organization,
      me: "/api/org/#{organization.slug}/me",
      admin: "/api/org/#{organization.slug}/admin",
      public: "/api/public/sites/#{organization.slug}"
    }
  end

  defp as(user), do: put_bearer_token(build_conn(), user)

  test "only people who checked in review, once each; the box replies, never deletes", ctx do
    Application.put_env(:palee, :fake_review_signals, %{attendance_count: 0})

    assert %{"can_review" => false, "mine" => nil, "count" => 0, "average" => nil} =
             ctx.newcomer |> as() |> get("#{ctx.me}/box-reviews") |> json_response(200)

    assert %{"code" => "review_needs_check_in"} =
             ctx.newcomer
             |> as()
             |> put("#{ctx.me}/box-review", %{rating: 5})
             |> json_response(403)

    Application.put_env(:palee, :fake_review_signals, %{attendance_count: 3})

    assert %{"errors" => _} =
             ctx.member |> as() |> put("#{ctx.me}/box-review", %{rating: 6}) |> json_response(422)

    assert %{"review" => %{"id" => id, "rating" => 4, "author_name" => "Ελένη", "edited_at" => nil}} =
             ctx.member
             |> as()
             |> put("#{ctx.me}/box-review", %{rating: 4, body: "  Καλοί coaches. "})
             |> json_response(200)

    # A second write edits the first.
    assert %{"review" => %{"id" => ^id, "rating" => 2, "body" => "Πολύς κόσμος.", "edited_at" => edited}} =
             ctx.member
             |> as()
             |> put("#{ctx.me}/box-review", %{rating: 2, body: "Πολύς κόσμος."})
             |> json_response(200)

    assert is_binary(edited)

    # Every review counts, whatever its stars.
    assert %{"count" => 1, "average" => 2.0, "reviews" => [%{"id" => ^id}], "google" => nil} =
             ctx.owner |> as() |> get("#{ctx.admin}/box-reviews") |> json_response(200)

    assert %{"review" => %{"reply" => %{"body" => "Ευχαριστούμε, φτιάχνουμε ώρες."}}} =
             ctx.owner
             |> as()
             |> put("#{ctx.admin}/box-reviews/#{id}/reply", %{body: "Ευχαριστούμε, φτιάχνουμε ώρες."})
             |> json_response(200)

    ctx.owner
    |> as()
    |> put("#{ctx.admin}/box-reviews/#{Ecto.UUID.generate()}/reply", %{body: "x"})
    |> json_response(404)

    # Members do not reply; there is no staff delete at all.
    ctx.member
    |> as()
    |> put("#{ctx.admin}/box-reviews/#{id}/reply", %{body: "x"})
    |> json_response(403)

    assert %{"mine" => %{"id" => ^id, "reply" => %{"body" => _}}, "can_review" => true} =
             ctx.member |> as() |> get("#{ctx.me}/box-reviews") |> json_response(200)

    # The website shows the count, average and latest, apart from Google.
    assert %{"reviews" => %{"palee" => %{"count" => 1, "latest" => [%{"author_name" => "Ελένη"}]}}} =
             site = build_conn() |> get(ctx.public) |> json_response(200)

    assert "reviews" in site["sections"]

    ctx.member |> as() |> delete("#{ctx.me}/box-review") |> response(204)

    assert %{"count" => 0, "reviews" => []} =
             ctx.owner |> as() |> get("#{ctx.admin}/box-reviews") |> json_response(200)
  end

  test "the Google listing: found by name, read at once, shown apart (sandbox)", ctx do
    assert %{"places" => [%{"place_id" => place_id, "name" => "Box Κυψέλη"}]} =
             ctx.owner
             |> as()
             |> get("#{ctx.admin}/review-asks/places?q=Box%20%CE%9A%CF%85%CF%88%CE%AD%CE%BB%CE%B7")
             |> json_response(200)

    assert %{"code" => "invalid_place_query"} =
             ctx.owner |> as() |> get("#{ctx.admin}/review-asks/places?q=ab") |> json_response(422)

    assert %{"google" => %{"rating" => 4.8, "count" => 126, "reviews" => [review]}} =
             ctx.owner
             |> as()
             |> put("#{ctx.admin}/review-asks/settings", %{lock_version: 0, google_place_id: place_id})
             |> json_response(200)

    assert %{"author_name" => "Μαρία Π.", "rating" => 5, "relative_time" => _} = review

    assert %{"google" => %{"rating" => 4.8}, "count" => 0} =
             ctx.member |> as() |> get("#{ctx.me}/box-reviews") |> json_response(200)

    site = build_conn() |> get(ctx.public) |> json_response(200)
    assert "reviews" in site["sections"]
    assert %{"google" => %{"count" => 126}, "google_reviews_url" => url} = site["reviews"]
    assert url =~ place_id

    # A place Google no longer knows empties the listing.
    assert %{"google" => nil} =
             ctx.owner
             |> as()
             |> put("#{ctx.admin}/review-asks/settings", %{
               lock_version: 1,
               google_place_id: "missing_place_123"
             })
             |> json_response(200)

    ctx.member |> as() |> get("#{ctx.admin}/review-asks/places?q=abcd") |> json_response(403)
  end
end

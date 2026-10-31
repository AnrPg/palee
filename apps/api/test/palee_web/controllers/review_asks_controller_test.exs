defmodule PaleeWeb.ReviewAsksControllerTest do
  @moduledoc """
  ADR-355 as the RLS runtime role: staff set the Place ID, a member past a
  milestone is asked once, answers, can opt out; staff see counts only.
  """

  use PaleeWeb.ConnCase, async: false

  import Palee.TestFixtures

  alias Palee.Organizations

  @place "ChIJN1t_tDeuEmsRUsoyG83frY4"

  setup do
    previous =
      {Application.get_env(:palee, :review_signals),
       Application.get_env(:palee, :review_ask_clock)}

    Application.put_env(:palee, :review_signals, Palee.TestSupport.FakeReviewSignals)
    Application.put_env(:palee, :review_ask_clock, Palee.TestSupport.FixedReviewAskClock)

    on_exit(fn ->
      Application.put_env(:palee, :review_signals, elem(previous, 0))
      Application.put_env(:palee, :review_ask_clock, elem(previous, 1))
      Application.delete_env(:palee, :fake_review_signals)
    end)

    owner = admin_fixture()
    member = user_fixture()

    {:ok, organization} =
      Organizations.create_organization(%{
        name: "Review Box #{System.unique_integer([:positive])}"
      })

    for {user, role} <- [{owner, :owner}, {member, :member}] do
      {:ok, _membership} =
        Organizations.add_membership(%{
          organization_id: organization.id,
          user_id: user.id,
          role: role,
          status: :active,
          joined_at: DateTime.utc_now()
        })
    end

    %{
      owner: owner,
      member: member,
      admin: "/api/org/#{organization.slug}/admin/review-asks",
      me: "/api/org/#{organization.slug}/me"
    }
  end

  defp as(user), do: put_bearer_token(build_conn(), user)

  test "off until a Place ID is set; then asked once, answered, opted out", ctx do
    assert %{"ask" => nil} =
             ctx.member |> as() |> get("#{ctx.me}/review-ask") |> json_response(200)

    assert %{"errors" => _} =
             ctx.owner
             |> as()
             |> put("#{ctx.admin}/settings", %{lock_version: 0, google_place_id: "bad id"})
             |> json_response(422)

    assert %{"settings" => %{"enabled" => true, "google_review_url" => url}} =
             ctx.owner
             |> as()
             |> put("#{ctx.admin}/settings", %{
               lock_version: 0,
               enabled: true,
               google_place_id: @place
             })
             |> json_response(200)

    assert url =~ @place

    assert %{
             "ask" => %{
               "id" => id,
               "milestone" => 10,
               "google_review_url" => ^url,
               "status" => "shown"
             }
           } =
             ctx.member |> as() |> get("#{ctx.me}/review-ask") |> json_response(200)

    # Closed without answering: the same ask comes back.
    assert %{"ask" => %{"id" => ^id}} =
             ctx.member |> as() |> get("#{ctx.me}/review-ask") |> json_response(200)

    assert %{"ask" => %{"status" => "opened"}} =
             ctx.member
             |> as()
             |> post("#{ctx.me}/review-asks/#{id}/respond", %{action: "opened"})
             |> json_response(200)

    assert %{"code" => "review_ask_answered"} =
             ctx.member
             |> as()
             |> post("#{ctx.me}/review-asks/#{id}/respond", %{action: "later"})
             |> json_response(409)

    # Answered: no new ask (milestone asked, cooldown).
    assert %{"ask" => nil} =
             ctx.member |> as() |> get("#{ctx.me}/review-ask") |> json_response(200)

    # Another member's ask is not theirs to answer.
    ctx.owner
    |> as()
    |> post("#{ctx.me}/review-asks/#{id}/respond", %{action: "later"})
    |> json_response(404)

    assert %{"opted_out" => true} =
             ctx.member |> as() |> put("#{ctx.me}/review-asks/opt-out") |> json_response(200)

    assert %{"counts" => %{"asked" => 1, "opened" => 1, "opted_out" => 1}} =
             ctx.owner |> as() |> get("#{ctx.admin}/summary") |> json_response(200)

    assert %{"opted_out" => false} =
             ctx.member |> as() |> delete("#{ctx.me}/review-asks/opt-out") |> json_response(200)

    # Members do not see the settings.
    ctx.member |> as() |> get("#{ctx.admin}/settings") |> json_response(403)
  end

  test "opted-out members and members without the moment are never asked", ctx do
    ctx.owner
    |> as()
    |> put("#{ctx.admin}/settings", %{lock_version: 0, enabled: true, google_place_id: @place})
    |> json_response(200)

    Application.put_env(:palee, :fake_review_signals, %{attendance_count: 7})

    assert %{"ask" => nil} =
             ctx.member |> as() |> get("#{ctx.me}/review-ask") |> json_response(200)

    Application.put_env(:palee, :fake_review_signals, %{})
    ctx.member |> as() |> put("#{ctx.me}/review-asks/opt-out") |> json_response(200)

    assert %{"ask" => nil} =
             ctx.member |> as() |> get("#{ctx.me}/review-ask") |> json_response(200)
  end
end

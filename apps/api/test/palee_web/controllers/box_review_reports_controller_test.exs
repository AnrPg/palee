defmodule PaleeWeb.BoxReviewReportsControllerTest do
  @moduledoc """
  ADR-397 as the RLS runtime role: members and the box report a review, which
  stays up until the Palee team decides; only the Palee team hides or
  removes, everyone concerned hears it, and the author reads the reasons.
  """

  use PaleeWeb.ConnCase, async: false

  import Palee.TestFixtures

  alias Palee.{Notifications, Organizations, Repo}

  setup do
    previous = Application.get_env(:palee, :review_signals)
    Application.put_env(:palee, :review_signals, Palee.TestSupport.FakeReviewSignals)
    Application.put_env(:palee, :fake_review_signals, %{attendance_count: 3})

    on_exit(fn ->
      Application.put_env(:palee, :review_signals, previous)
      Application.delete_env(:palee, :fake_review_signals)
    end)

    owner = admin_fixture()
    author = user_fixture(%{display_name: "Ελένη Παπαδοπούλου"})
    reporter = user_fixture()
    other = user_fixture()
    vendor = user_fixture()
    bypass_rls(fn -> {:ok, _vendor} = Organizations.grant_vendor(vendor.id) end)

    {:ok, organization} =
      Organizations.create_organization(%{
        name: "Report Box #{System.unique_integer([:positive])}"
      })

    for {user, role} <- [
          {owner, :owner},
          {author, :member},
          {reporter, :member},
          {other, :member}
        ] do
      {:ok, _membership} =
        Organizations.add_membership(%{
          organization_id: organization.id,
          user_id: user.id,
          role: role,
          status: :active,
          joined_at: DateTime.utc_now()
        })
    end

    me = "/api/org/#{organization.slug}/me"

    %{"review" => %{"id" => review_id}} =
      author
      |> as()
      |> put("#{me}/box-review", %{rating: 1, body: "Ο coach Γιώργος είναι ηλίθιος."})
      |> json_response(200)

    %{
      owner: owner,
      author: author,
      reporter: reporter,
      other: other,
      vendor: vendor,
      organization: organization,
      review_id: review_id,
      me: me,
      admin: "/api/org/#{organization.slug}/admin"
    }
  end

  defp as(user), do: put_bearer_token(build_conn(), user)

  defp notices(user, type),
    do: user.id |> Notifications.list_for_user() |> Enum.filter(&(to_string(&1.type) == type))

  defp report(ctx, user, params, path \\ :me) do
    base = if path == :me, do: ctx.me, else: ctx.admin
    user |> as() |> post("#{base}/box-reviews/#{ctx.review_id}/report", params)
  end

  test "a report changes nothing until the Palee team hides the review", ctx do
    %{review_id: review_id} = ctx

    # Nobody reports their own review; reasons are a fixed list.
    assert %{"code" => "cannot_report_own_review"} =
             ctx |> report(ctx.author, %{reason: "offensive"}) |> json_response(422)

    assert %{"errors" => _} =
             ctx |> report(ctx.reporter, %{reason: "boring"}) |> json_response(422)

    assert %{"errors" => %{"note" => _}} =
             ctx |> report(ctx.reporter, %{reason: "other"}) |> json_response(422)

    assert %{"review_id" => ^review_id, "status" => "open"} =
             ctx
             |> report(ctx.reporter, %{reason: "offensive", note: "Βρίζει τον coach."})
             |> json_response(200)

    # Reporting twice is the same open report.
    assert %{"status" => "open"} =
             ctx |> report(ctx.reporter, %{reason: "offensive"}) |> json_response(200)

    # The box reports as the box; members cannot use the box's route.
    ctx |> report(ctx.other, %{reason: "offensive"}, :admin) |> json_response(403)

    assert %{"status" => "open"} =
             ctx |> report(ctx.owner, %{reason: "not_genuine"}, :admin) |> json_response(200)

    # Still up and counted for everyone; the reporter knows they reported it.
    assert %{"count" => 1, "reviews" => [%{"id" => ^review_id}], "reported_ids" => [^review_id]} =
             ctx.reporter |> as() |> get("#{ctx.me}/box-reviews") |> json_response(200)

    assert %{"count" => 1, "average" => 1.0} =
             ctx.owner |> as() |> get("#{ctx.admin}/box-reviews") |> json_response(200)

    # Only the Palee team sees the queue.
    assert %{"code" => "vendor_required"} =
             ctx.owner |> as() |> get("/api/platform/review-reports") |> json_response(403)

    assert %{"items" => items, "decisions" => []} =
             ctx.vendor |> as() |> get("/api/platform/review-reports") |> json_response(200)

    assert [item] = Enum.filter(items, &(&1["review_id"] == review_id))

    assert %{
             "reports_count" => 2,
             "box_reported" => true,
             "author_name" => "Ελένη",
             "reported" => %{"rating" => 1, "body" => "Ο coach Γιώργος είναι ηλίθιος."},
             "current" => %{"rating" => 1},
             "notes" => [%{"role" => "member", "note" => "Βρίζει τον coach."}]
           } = item

    assert item["organization"]["name"] == ctx.organization.name
    refute inspect(item) =~ ctx.reporter.id

    decide = fn params ->
      ctx.vendor
      |> as()
      |> post("/api/platform/review-reports/#{review_id}/decision", params)
    end

    assert %{"errors" => %{"statement" => _}} =
             decide.(%{outcome: "hide", ground: "offensive"}) |> json_response(422)

    assert %{"outcome" => "hide", "ground" => "offensive", "resolved" => 2} =
             decide.(%{
               outcome: "hide",
               ground: "offensive",
               statement: "Η κριτική προσβάλλει έναν coach με το όνομά του."
             })
             |> json_response(200)

    assert %{"code" => "review_report_decided"} =
             decide.(%{outcome: "keep"}) |> json_response(409)

    # Out of every list and the average; the author reads why.
    assert %{"count" => 0, "average" => nil, "reviews" => [], "reported_ids" => []} =
             ctx.reporter |> as() |> get("#{ctx.me}/box-reviews") |> json_response(200)

    assert %{
             "mine" => %{
               "id" => ^review_id,
               "body" => "Ο coach Γιώργος είναι ηλίθιος.",
               "moderation" => %{
                 "status" => "hidden",
                 "outcome" => "hide",
                 "ground" => "offensive",
                 "legal_basis" => "terms",
                 "statement" => "Η κριτική προσβάλλει έναν coach με το όνομά του.",
                 "after_report" => true,
                 "automated" => false,
                 "redress" => ["contact_palee", "court"],
                 "contact" => "moderation@palee.app"
               }
             }
           } = ctx.author |> as() |> get("#{ctx.me}/box-reviews") |> json_response(200)

    # Neither the author edits nor the box replies; a hidden review is not reported again.
    assert %{"code" => "review_moderated"} =
             ctx.author
             |> as()
             |> put("#{ctx.me}/box-review", %{rating: 2, body: "Άλλο κείμενο"})
             |> json_response(409)

    assert %{"code" => "review_moderated"} =
             ctx.owner
             |> as()
             |> put("#{ctx.admin}/box-reviews/#{review_id}/reply", %{body: "Λυπούμαστε"})
             |> json_response(409)

    assert %{"code" => "box_review_not_found"} =
             ctx |> report(ctx.other, %{reason: "spam"}) |> json_response(404)

    # Everyone concerned hears it.
    assert [%{payload: %{"outcome" => "hide"}}] =
             notices(ctx.reporter, "box_review_report_decided")

    assert [_] = notices(ctx.owner, "box_review_report_decided")
    assert [%{payload: %{"ground" => "offensive"}}] = notices(ctx.author, "box_review_moderated")

    # The audit trail: who decided and when.
    assert %{"items" => [], "decisions" => decisions} =
             ctx.vendor
             |> as()
             |> get("/api/platform/review-reports?status=decided")
             |> json_response(200)

    assert [%{"outcome" => "hide", "reports_count" => 2, "decided_by" => decided_by}] =
             Enum.filter(decisions, &(&1["review_id"] == review_id))

    assert is_binary(decided_by)

    assert Enum.all?(
             Enum.filter(decisions, &(&1["review_id"] == review_id)),
             &(&1["review_status"] == "hidden")
           )

    # Restoring needs a statement; then the review is back and the author hears it.
    restore = fn params ->
      ctx.vendor |> as() |> post("/api/platform/review-reports/#{review_id}/restore", params)
    end

    assert %{"errors" => _} = restore.(%{}) |> json_response(422)

    ctx.owner
    |> as()
    |> post("/api/platform/review-reports/#{review_id}/restore", %{statement: "x"})
    |> json_response(403)

    assert %{"outcome" => "restore", "resolved" => 0} =
             restore.(%{statement: "Το ξαναδείξαμε: ο coach δεν κατονομάζεται πια."})
             |> json_response(200)

    assert %{"code" => "review_not_hidden"} = restore.(%{statement: "Ξανά"}) |> json_response(409)

    assert %{"count" => 1, "reviews" => [%{"id" => ^review_id}]} =
             ctx.reporter |> as() |> get("#{ctx.me}/box-reviews") |> json_response(200)

    assert %{"mine" => %{"moderation" => nil}} =
             ctx.author |> as() |> get("#{ctx.me}/box-reviews") |> json_response(200)

    assert [_restored] =
             ctx.author
             |> notices("box_review_moderated")
             |> Enum.filter(&(&1.payload["outcome"] == "restore"))

    assert %{"decisions" => [%{"outcome" => "restore", "review_status" => "visible"} | _]} =
             ctx.vendor
             |> as()
             |> get("/api/platform/review-reports?status=decided")
             |> json_response(200)

    # The author may still delete it.
    ctx.author |> as() |> delete("#{ctx.me}/box-review") |> response(204)
  end

  test "remove erases the text and the reply; keep tells only the reporter", ctx do
    ctx.owner
    |> as()
    |> put("#{ctx.admin}/box-reviews/#{ctx.review_id}/reply", %{body: "Λυπούμαστε."})
    |> json_response(200)

    ctx |> report(ctx.reporter, %{reason: "offensive"}) |> json_response(200)

    assert %{"outcome" => "keep", "ground" => "no_violation", "resolved" => 1} =
             ctx.vendor
             |> as()
             |> post("/api/platform/review-reports/#{ctx.review_id}/decision", %{outcome: "keep"})
             |> json_response(200)

    assert [%{payload: %{"outcome" => "keep"}}] =
             notices(ctx.reporter, "box_review_report_decided")

    assert [] = notices(ctx.author, "box_review_moderated")

    assert %{"count" => 1} =
             ctx.reporter |> as() |> get("#{ctx.me}/box-reviews") |> json_response(200)

    # A new report after a decision opens a new case.
    ctx |> report(ctx.other, %{reason: "personal_data"}) |> json_response(200)

    assert %{"outcome" => "remove", "resolved" => 1} =
             ctx.vendor
             |> as()
             |> post("/api/platform/review-reports/#{ctx.review_id}/decision", %{
               outcome: "remove",
               ground: "personal_data",
               statement: "Ονομάζει coach και τον προσβάλλει."
             })
             |> json_response(200)

    assert %{
             "mine" => %{
               "body" => nil,
               "reply" => nil,
               "moderation" => %{"status" => "removed", "outcome" => "remove"}
             }
           } = ctx.author |> as() |> get("#{ctx.me}/box-reviews") |> json_response(200)

    assert [%{payload: %{"outcome" => "remove"}}] = notices(ctx.author, "box_review_moderated")

    # The reporter's own reports go with a profile kept anonymised.
    count = fn ->
      bypass_rls(fn ->
        %{rows: [[n]]} =
          Repo.query!("SELECT count(*) FROM box_review_reports WHERE reporter_id = $1", [
            Ecto.UUID.dump!(ctx.other.id)
          ])

        n
      end)
    end

    assert count.() == 1

    Palee.DataCase.with_runtime_role(fn ->
      Repo.query!("SELECT palee_forget_box_review_reports($1)", [Ecto.UUID.dump!(ctx.other.id)])
    end)

    assert count.() == 0
  end

  test "the daily job: removed texts go after 6 months, a summary while reports wait", ctx do
    alias Palee.Application.ReviewAsks.ReviewReportsDaily

    ctx |> report(ctx.reporter, %{reason: "spam"}) |> json_response(200)

    now = DateTime.utc_now()
    assert %{summary: {:ok, message}} = ReviewReportsDaily.run(now)
    assert message.kind in [:review_reports_summary, "review_reports_summary"]

    ctx.vendor
    |> as()
    |> post("/api/platform/review-reports/#{ctx.review_id}/decision", %{
      outcome: "remove",
      ground: "spam",
      statement: "Διαφήμιση."
    })
    |> json_response(200)

    copy = fn ->
      bypass_rls(fn ->
        %{rows: [[body]]} =
          Repo.query!("SELECT review_body FROM box_review_reports WHERE review_id = $1", [
            Ecto.UUID.dump!(ctx.review_id)
          ])

        body
      end)
    end

    assert %{cleared: 0, summary: :none} = ReviewReportsDaily.run(now)
    assert copy.() == "Ο coach Γιώργος είναι ηλίθιος."
    assert %{cleared: cleared} = ReviewReportsDaily.run(DateTime.add(now, 184 * 86_400, :second))
    assert cleared >= 1
    assert copy.() == nil
  end

  test "the box's website names where to report content", ctx do
    {:ok, context} = Organizations.resolve_tenant_context(ctx.owner, ctx.organization.slug)

    {:ok, profile} =
      Palee.Application.UpdateBoxPublicProfile.call(context, %{
        "about" => "Box",
        "disciplines" => ["crossfit"]
      })

    {:ok, _profile} =
      Palee.Application.PublishBoxPublicProfile.publish(context, %{
        "lock_version" => profile.lock_version
      })

    assert %{"report_contact" => "moderation@palee.app"} =
             build_conn()
             |> get("/api/public/sites/#{ctx.organization.slug}")
             |> json_response(200)
  end

  test "decisions need the Palee team and a reported review", ctx do
    ctx.owner
    |> as()
    |> post("/api/platform/review-reports/#{ctx.review_id}/decision", %{outcome: "keep"})
    |> json_response(403)

    assert %{"code" => "box_review_not_found"} =
             ctx.vendor
             |> as()
             |> post("/api/platform/review-reports/#{ctx.review_id}/decision", %{outcome: "keep"})
             |> json_response(404)

    ctx.vendor
    |> as()
    |> get("/api/platform/review-reports?status=closed")
    |> json_response(422)
  end
end

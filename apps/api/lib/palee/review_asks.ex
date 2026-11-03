defmodule Palee.ReviewAsks do
  @moduledoc """
  The ReviewAsks bounded context (ADR-355): asking members for a Google
  review at a good moment, the same way for everyone, never gated by their
  opinion and never rewarded, with an opt-out; the box's in-app reviews
  (ADR-386) and its Google listing snapshot (ADR-387).
  """

  alias Palee.ReviewAsks.Domain.{
    BoxReviewPolicy,
    GooglePlacePolicy,
    ReviewAskPolicy,
    ReviewReportPolicy,
    TenantDataPolicy
  }

  alias Palee.ReviewAsks.ReviewAskStore

  @doc "The configured clock (`ReviewAsks.Ports.Clock`)."
  def clock, do: Application.fetch_env!(:palee, :review_ask_clock)
  @doc "The configured signals (`ReviewAsks.Ports.ReviewSignals`)."
  def signals, do: Application.fetch_env!(:palee, :review_signals)
  @doc "The configured Google listing adapter (`ReviewAsks.Ports.Places`, ADR-387)."
  def places, do: Application.fetch_env!(:palee, :google_places)

  @doc "The box's settings, or the defaults (asks off)."
  def settings(context),
    do: ReviewAskStore.get_settings(context) || ReviewAskPolicy.default_settings()

  @doc "Saves an edit (string keys) against its `lock_version`."
  def update_settings(context, params, user_id) do
    current = settings(context)

    with {:ok, changes} <- ReviewAskPolicy.changes(current, params) do
      lock = Map.get(params, "lock_version", current.lock_version)

      case ReviewAskStore.save_settings(context, Map.put(changes, :updated_by_id, user_id), lock) do
        {:error, :stale} -> {:error, :settings_changed_meanwhile}
        result -> result
      end
    end
  end

  defdelegate list_asks(context, user_id), to: ReviewAskStore
  defdelegate get_ask(context, id, user_id), to: ReviewAskStore
  defdelegate opted_out?(context, user_id), to: ReviewAskStore
  defdelegate opt_out(context, user_id, now), to: ReviewAskStore
  defdelegate opt_in(context, user_id), to: ReviewAskStore
  defdelegate summary(context, since), to: ReviewAskStore
  defdelegate decide(settings, facts, asks, opted_out?, local_hour, now), to: ReviewAskPolicy
  defdelegate write_review_url(place_id), to: ReviewAskPolicy
  defdelegate read_reviews_url(place_id), to: ReviewAskPolicy
  defdelegate actions(), to: ReviewAskPolicy

  @doc "Records an ask shown to a member now."
  def record_ask(context, user_id, milestone, now) do
    ReviewAskStore.insert_ask(context, %{
      user_id: user_id,
      trigger: "attendance_milestone",
      milestone: milestone,
      status: "shown",
      shown_at: now
    })
  end

  @doc "Records a member's answer to their own ask."
  def respond(context, user_id, id, action, now) do
    with %{} = ask <-
           ReviewAskStore.get_ask(context, id, user_id) || {:error, :review_ask_not_found},
         {:ok, changes} <- ReviewAskPolicy.respond(ask, action, now) do
      if changes == %{}, do: {:ok, ask}, else: ReviewAskStore.update_ask(context, ask.id, changes)
    end
  end

  # ── In-app reviews (ADR-386) ────────────────────────────────────────────

  defdelegate get_review(context, user_id), to: ReviewAskStore
  defdelegate get_review_by_id(context, id), to: ReviewAskStore
  defdelegate list_reviews(context, page), to: ReviewAskStore
  defdelegate may_review(facts), to: BoxReviewPolicy
  defdelegate author_name(name), to: BoxReviewPolicy
  defdelegate public_latest(), to: BoxReviewPolicy

  @doc "The count and average stars of the box's in-app reviews."
  def review_stats(context) do
    stats = ReviewAskStore.review_stats(context)
    %{count: stats.count, average: BoxReviewPolicy.average(stats)}
  end

  @doc "Writes or edits the person's own review (string-key params)."
  def save_review(context, user_id, params, locale, now) do
    current = ReviewAskStore.get_review(context, user_id)

    with :ok <- ReviewReportPolicy.editable(current),
         {:ok, review} <- BoxReviewPolicy.review(params) do
      edited = if current, do: now, else: nil

      attrs =
        review
        |> Map.put(:locale, locale)
        |> then(&if(edited, do: Map.put(&1, :edited_at, edited), else: &1))

      ReviewAskStore.save_review(context, user_id, attrs)
    end
  end

  @doc "The author deletes their own review."
  defdelegate delete_review(context, user_id), to: ReviewAskStore

  @doc "The box replies to a review (or edits its reply); it can never delete one."
  def reply_review(context, id, params, staff_id, now) do
    with %{} = review <-
           ReviewAskStore.get_review_by_id(context, id) || {:error, :box_review_not_found},
         :ok <- ReviewReportPolicy.editable(review),
         {:ok, body} <- BoxReviewPolicy.reply(params) do
      ReviewAskStore.reply_review(context, id, %{
        reply_body: body,
        replied_at: now,
        replied_by_id: staff_id
      })
    end
  end

  # ── Reports and the Palee team's decisions (ADR-397) ────────────────────

  defdelegate report_reasons(), to: ReviewReportPolicy, as: :reasons
  defdelegate report_statuses(), to: ReviewReportPolicy, as: :statuses
  defdelegate removed_text_before(now), to: ReviewReportPolicy
  defdelegate purge_removed_texts(before), to: ReviewAskStore
  defdelegate open_report_totals(), to: ReviewAskStore

  @doc """
  The Palee team's moderation settings (`config :palee, :review_moderation`):
  `contact_email` (named in every statement of reasons and in the box
  website's footer), `team_email` and `team_locale` (the daily summary).
  """
  def moderation_config, do: Application.get_env(:palee, :review_moderation, [])

  @doc "Where anyone reports content or asks for a decision to be looked at again."
  def moderation_contact, do: Keyword.get(moderation_config(), :contact_email)

  @doc "The statement of reasons with Palee's moderation contact (DSA Art. 17(3)(f))."
  def statement_of_reasons(decision),
    do: ReviewReportPolicy.statement_of_reasons(decision, moderation_contact())
  defdelegate reported_review_ids(context, reporter_id), to: ReviewAskStore
  defdelegate latest_decision(context, review_id), to: ReviewAskStore
  defdelegate platform_open_reports(context, limit), to: ReviewAskStore
  defdelegate platform_decisions(context, limit), to: ReviewAskStore
  defdelegate platform_review_organization(context, review_id), to: ReviewAskStore

  @doc """
  Files a report on a review (string-key params) as `role` (`member` or
  `box`). Nothing changes for anyone until the Palee team decides; a second
  report by the same person while one is open is `:already_reported`.
  """
  def report_review(%{user_id: reporter_id} = context, review_id, role, params, now)
      when role in ["member", "box"] do
    with %{} = review <-
           ReviewAskStore.get_review_by_id(context, review_id) || {:error, :box_review_not_found},
         :ok <- ReviewReportPolicy.may_report(review, reporter_id),
         {:ok, report} <- ReviewReportPolicy.report(params),
         :ok <-
           ReviewReportPolicy.within_limit(
             ReviewAskStore.count_reports_since(
               context,
               reporter_id,
               ReviewReportPolicy.limit_since(now)
             )
           ) do
      ReviewAskStore.insert_report(context, %{
        review_id: review.id,
        review_author_id: review.user_id,
        reporter_id: reporter_id,
        reporter_role: role,
        reason: report.reason,
        note: report.note,
        review_rating: review.rating,
        review_body: review.body
      })
    end
  end

  @doc """
  The Palee team decides on a review, in the box's own session: the review
  changes, a decision row holds the statement of reasons and every open
  report on the review closes with the outcome.
  """
  def decide_review(context, review_id, params, decided_by_id, now) do
    with {:ok, decision} <- ReviewReportPolicy.decision(params) do
      ReviewAskStore.decide_review(
        context,
        review_id,
        ReviewReportPolicy.review_changes(decision.outcome, now),
        Map.merge(decision, %{decided_by_id: decided_by_id, decided_at: now}),
        ReviewReportPolicy.report_status(decision.outcome)
      )
    end
  end

  @doc """
  The Palee team shows a hidden review again, with a statement for the
  author; a removed review cannot come back (its text is gone).
  """
  def restore_review(context, review_id, params, decided_by_id, now) do
    with {:ok, decision} <- ReviewReportPolicy.restore(params) do
      ReviewAskStore.restore_review(
        context,
        review_id,
        ReviewReportPolicy.review_changes("restore", now),
        Map.merge(decision, %{decided_by_id: decided_by_id, decided_at: now})
      )
    end
  end

  # ── Google listing (ADR-387) ────────────────────────────────────────────

  defdelegate place_query(value), to: GooglePlacePolicy, as: :query
  defdelegate place_snapshot(context), to: ReviewAskStore, as: :get_place_snapshot
  defdelegate place_due_organizations(now), to: ReviewAskStore

  @doc "The snapshot to show for the box's current Place ID, or nil."
  def visible_place(context, place_id, now),
    do: GooglePlacePolicy.visible(ReviewAskStore.get_place_snapshot(context), place_id, now)

  @doc "Reads the listing now and stores the snapshot (or the failure)."
  def refresh_place(context, place_id, language, now) do
    current = ReviewAskStore.get_place_snapshot(context)

    attrs =
      case places().details(place_id, language: language) do
        {:ok, details} ->
          GooglePlacePolicy.snapshot(place_id, details, now)

        {:error, reason} ->
          attempts = if current && current.place_id == place_id, do: current.attempts, else: 0

          place_id
          |> GooglePlacePolicy.failure(reason, attempts, now)
          |> Map.put_new(:fetched_at, (current && current.fetched_at) || now)
          |> then(&if(current && current.place_id != place_id, do: reset(&1), else: &1))
      end

    ReviewAskStore.save_place_snapshot(context, attrs)
  end

  # A failed first read of a new place drops the old place's data.
  defp reset(attrs),
    do: Map.merge(%{name: nil, rating: nil, rating_count: nil, maps_uri: nil, reviews: []}, attrs)

  def tenant_data_policy, do: TenantDataPolicy.policy()

  def tenant_data_inventory(context),
    do: Palee.TenantData.TableStore.inventory(tenant_data_policy(), context)

  def export_tenant_data(context, mode \\ :full),
    do: Palee.TenantData.TableStore.export(tenant_data_policy(), context, mode)

  def purge_tenant_data(context),
    do: Palee.TenantData.TableStore.purge(tenant_data_policy(), context)
end

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
    with {:ok, review} <- BoxReviewPolicy.review(params) do
      edited = if ReviewAskStore.get_review(context, user_id), do: now, else: nil

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
    with {:ok, body} <- BoxReviewPolicy.reply(params) do
      ReviewAskStore.reply_review(context, id, %{
        reply_body: body,
        replied_at: now,
        replied_by_id: staff_id
      })
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

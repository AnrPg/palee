defmodule Palee.Application.ReviewAsks.MemberReviewAsk do
  @moduledoc """
  ADR-355: the member's side of a Google review ask. The app calls `current/1`
  when it opens (after a class); the policy decides then, the same way for
  everyone, and the ask is recorded when shown.

  ADR-386: an ask is answered only on the visit that showed it: the next
  call never returns it again (no reminders). The card offers the in-app
  review, the Google review when the box set its Place ID, and a private
  message to the box.
  """

  alias Palee.{Organizations, ReviewAsks}

  @doc "The ask to show now, or nil."
  def current(%{organization_id: organization_id, user_id: user_id} = context) do
    now = ReviewAsks.clock().now()
    settings = ReviewAsks.settings(context)
    asks = ReviewAsks.list_asks(context, user_id)

    facts = ReviewAsks.signals().facts(context, user_id)
    opted_out = ReviewAsks.opted_out?(context, user_id)
    hour = local_hour(organization_id, now)

    case ReviewAsks.decide(settings, facts, asks, opted_out, hour, now) do
      {:ask, milestone} ->
        case ReviewAsks.record_ask(context, user_id, milestone, now) do
          {:ok, ask} -> {:ok, %{ask: present(ask, settings, context, user_id)}}
          {:error, _already} -> {:ok, %{ask: nil}}
        end

      {:skip, _reason} ->
        {:ok, %{ask: nil}}
    end
  end

  @doc "Records the member's answer: `opened`, `later` or `dismissed`."
  def respond(%{user_id: user_id} = context, id, action) do
    with {:ok, ask} <- ReviewAsks.respond(context, user_id, id, action, ReviewAsks.clock().now()) do
      {:ok, %{ask: present(ask, ReviewAsks.settings(context), context, user_id)}}
    end
  end

  @doc "Never ask this member again (`true`), or allow asks again (`false`)."
  def set_opt_out(%{user_id: user_id} = context, true) do
    :ok = ReviewAsks.opt_out(context, user_id, ReviewAsks.clock().now())
    {:ok, %{opted_out: true}}
  end

  def set_opt_out(%{user_id: user_id} = context, false) do
    :ok = ReviewAsks.opt_in(context, user_id)
    {:ok, %{opted_out: false}}
  end

  defp present(ask, settings, context, user_id) do
    %{
      id: ask.id,
      milestone: ask.milestone,
      status: ask.status,
      shown_at: ask.shown_at,
      google_review_url: ReviewAsks.write_review_url(settings.google_place_id),
      has_review: not is_nil(ReviewAsks.get_review(context, user_id)),
      actions: ReviewAsks.actions()
    }
  end

  defp local_hour(organization_id, now) do
    zone = Organizations.organization_timezone(organization_id) || "Etc/UTC"

    case DateTime.shift_zone(now, zone) do
      {:ok, local} -> local.hour
      {:error, _reason} -> now.hour
    end
  end
end

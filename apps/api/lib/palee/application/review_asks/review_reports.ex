defmodule Palee.Application.ReviewAsks.ReviewReports do
  @moduledoc """
  ADR-397: «Αναφορά» on the in-app reviews of a box, decided only by the
  Palee team.

    * A member of the box, or the box itself (staff who reply as the box),
      reports a review with a fixed reason and an optional note. Nothing
      changes for anyone: the review stays up and counted until the Palee
      team decides, so a box can never hide a review on its own.
    * The Palee team's queue (vendor console) groups open reports per
      review across every box; a decision (`keep`, `hide`, `remove`, with a
      ground and a statement) closes every open report on that review. It is
      written in the box's own tenant session and in the vendors' audit log.
    * Every reporter hears the outcome; the author receives the statement of
      reasons when their review was hidden or removed (DSA Art. 16(5) and 17).
  """

  require Logger

  alias Palee.{Community, Identity, Notifications, Organizations, ReviewAsks}
  alias Palee.Organizations.PlatformContext

  @queue_limit 500
  @decided_limit 100
  @url "/box#reviews"

  @doc "A member reports a review of their box."
  def report_as_member(context, review_id, params),
    do: report(context, review_id, "member", params)

  @doc "The box (staff who speak as the box) reports a review of itself."
  def report_as_box(context, review_id, params),
    do: report(context, review_id, "box", params)

  defp report(context, review_id, role, params) do
    case ReviewAsks.report_review(context, review_id, role, stringify(params), now()) do
      {:ok, report} -> {:ok, %{review_id: report.review_id, status: report.status}}
      {:error, :already_reported} -> {:ok, %{review_id: review_id, status: "open"}}
      error -> error
    end
  end

  # ── The Palee team ──────────────────────────────────────────────────────

  @doc """
  The queue (`status` `open`, the default): one item per reported review,
  oldest first, with the review as reported and as it is now, the reasons
  and notes, and whether the box itself reported it. `decided`: the latest
  decisions, newest first (the audit trail).
  """
  def platform_queue(platform_context, params \\ %{})

  def platform_queue(%PlatformContext{} = platform, params) do
    case param(params, "status") || "open" do
      "open" -> {:ok, %{items: open_items(platform), decisions: []}}
      "decided" -> {:ok, %{items: [], decisions: decided(platform)}}
      _other -> {:error, :invalid_review_report_status}
    end
  end

  def platform_queue(_context, _params), do: {:error, :vendor_required}

  defp open_items(platform) do
    reports = ReviewAsks.platform_open_reports(platform, @queue_limit)

    names =
      Organizations.platform_organization_names(platform, Enum.map(reports, & &1.organization_id))

    reports
    |> Enum.group_by(& &1.review_id)
    |> Enum.map(fn {review_id, group} -> item(platform, review_id, group, names) end)
    |> Enum.sort_by(& &1.first_reported_at, DateTime)
  end

  defp item(platform, review_id, group, names) do
    first = Enum.min_by(group, & &1.inserted_at, DateTime)
    latest = Enum.max_by(group, & &1.inserted_at, DateTime)
    organization_id = first.organization_id
    current = ReviewAsks.get_review_by_id(tenant(platform, organization_id), review_id)

    %{
      review_id: review_id,
      organization: %{id: organization_id, name: Map.get(names, organization_id)},
      author_name: author_name(first.review_author_id),
      reported: %{rating: latest.review_rating, body: latest.review_body},
      current:
        current && %{rating: current.rating, body: current.body, edited_at: current.edited_at},
      reports_count: length(group),
      box_reported: Enum.any?(group, &(&1.reporter_role == "box")),
      reasons: group |> Enum.frequencies_by(& &1.reason) |> Enum.map(&reason_count/1),
      notes:
        group
        |> Enum.filter(& &1.note)
        |> Enum.map(
          &%{reason: &1.reason, role: &1.reporter_role, note: &1.note, at: &1.inserted_at}
        ),
      first_reported_at: first.inserted_at
    }
  end

  defp reason_count({reason, count}), do: %{reason: reason, count: count}

  defp decided(platform) do
    decisions = ReviewAsks.platform_decisions(platform, @decided_limit)

    names =
      Organizations.platform_organization_names(
        platform,
        Enum.map(decisions, & &1.organization_id)
      )

    deciders =
      decisions
      |> Enum.map(& &1.decided_by_id)
      |> Enum.reject(&is_nil/1)
      |> Identity.list_by_ids()
      |> Map.new(&{&1.id, display_name(&1)})

    Enum.map(decisions, fn decision ->
      %{
        id: decision.id,
        review_id: decision.review_id,
        organization: %{
          id: decision.organization_id,
          name: Map.get(names, decision.organization_id)
        },
        outcome: decision.outcome,
        ground: decision.ground,
        statement: decision.statement,
        reports_count: decision.reports_count,
        decided_by: Map.get(deciders, decision.decided_by_id),
        decided_at: decision.decided_at
      }
    end)
  end

  @doc """
  The Palee team decides on a reported review (string-key params `outcome`,
  `ground`, `statement`): for every open report on it, in the box's session,
  audited, and everyone concerned hears it.
  """
  def platform_decide(platform_context, review_id, params, now \\ nil)

  def platform_decide(%PlatformContext{user_id: vendor_id} = platform, review_id, params, now) do
    now = now || now()

    with organization_id when is_binary(organization_id) <-
           ReviewAsks.platform_review_organization(platform, review_id) ||
             {:error, :box_review_not_found},
         context = tenant(platform, organization_id),
         {:ok, result} <-
           ReviewAsks.decide_review(context, review_id, stringify(params), vendor_id, now),
         {:ok, _event} <-
           Organizations.record_platform_event(platform, organization_id, %{
             event: "box_review_moderated",
             metadata: %{
               review_id: review_id,
               outcome: result.decision.outcome,
               ground: result.decision.ground,
               reports: result.decision.reports_count
             }
           }) do
      notify(organization_id, result)

      {:ok,
       %{
         review_id: review_id,
         outcome: result.decision.outcome,
         ground: result.decision.ground,
         resolved: length(result.reports)
       }}
    end
  end

  def platform_decide(_context, _review_id, _params, _now), do: {:error, :vendor_required}

  # Reporters hear every outcome (DSA Art. 16(5)); the author hears a
  # restriction with its statement of reasons (Art. 17). A `keep` is not
  # sent to the author: nothing changed for them.
  defp notify(organization_id, %{decision: decision, reports: reports}) do
    reports
    |> Enum.map(& &1.reporter_id)
    |> Enum.uniq()
    |> Enum.each(fn reporter_id ->
      deliver("box_review_report_decided", %{
        user_id: reporter_id,
        organization_id: organization_id,
        review_id: decision.review_id,
        outcome: decision.outcome,
        dedupe_key: "box_review_report_decided:#{decision.id}:#{reporter_id}",
        url: @url
      })
    end)

    if decision.outcome != "keep" do
      deliver("box_review_moderated", %{
        user_id: decision.review_author_id,
        organization_id: organization_id,
        review_id: decision.review_id,
        outcome: decision.outcome,
        ground: decision.ground,
        dedupe_key: "box_review_moderated:#{decision.id}",
        url: @url
      })
    end

    :ok
  end

  defp deliver(type, payload) do
    Notifications.process_event(type, payload)
  rescue
    error -> Logger.warning("#{type} notice failed: #{Exception.message(error)}")
  end

  # ── helpers ─────────────────────────────────────────────────────────────

  defp tenant(%PlatformContext{user_id: user_id}, organization_id),
    do: %{organization_id: organization_id, user_id: user_id}

  # As the review shows (first name; nothing for people who hide themselves).
  defp author_name(user_id) do
    if user_id in Community.hidden_member_ids([user_id]) do
      nil
    else
      case Identity.list_by_ids([user_id]) do
        [user] -> ReviewAsks.author_name(display_name(user))
        _none -> nil
      end
    end
  end

  defp display_name(user),
    do: Map.get(user, :display_name) || Map.get(user, :nickname) || Map.get(user, :handle)

  defp param(params, key) do
    case Map.get(stringify(params), key) do
      value when is_binary(value) and value != "" -> value
      _other -> nil
    end
  end

  defp now, do: ReviewAsks.clock().now()

  defp stringify(params),
    do: Map.new(params || %{}, fn {key, value} -> {to_string(key), value} end)
end

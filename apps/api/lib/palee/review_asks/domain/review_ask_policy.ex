defmodule Palee.ReviewAsks.Domain.ReviewAskPolicy do
  @moduledoc """
  ADR-355: when a member is asked for a Google review.

  The ask goes to every member who reaches the same behavioural moment, never
  to a subset chosen by their opinion (Google forbids "selectively soliciting
  positive reviews"), and nothing is offered in return. Every rule below is
  the same for everyone:

    * asks are on;
    * the member did not opt out;
    * an active membership, held for at least #{30} days;
    * an attendance milestone just reached and never asked about (at most
      #{4} classes past it);
    * attended within the last #{2} days (right after a class);
    * daytime at the box (08:00–21:00 local);
    * no ask in the last #{120} days and fewer than #{3} in all.

  ADR-386 (v3.1): the card also offers the in-app review, so asks no longer
  need a Google Place ID (the Google button shows only with one), and an ask
  is shown once: it goes away after the visit it was shown in, with no
  reminder.

  Pure: callers bring the facts, the asks so far and the time.
  """

  @actions ~w(opened later dismissed)
  @statuses ["shown" | @actions]
  @min_member_days 30
  @milestone_slack 4
  @recent_attendance_days 2
  @cooldown_days 120
  @max_asks 3
  @day_hours 8..20
  @default_milestones [10, 50, 100]
  @place_id ~r/^[A-Za-z0-9_-]{10,300}$/

  def actions, do: @actions
  def statuses, do: @statuses
  def default_milestones, do: @default_milestones

  @doc "Default settings of a box that never saved any (asks off)."
  def default_settings do
    %{google_place_id: nil, enabled: false, milestones: @default_milestones, lock_version: 0}
  end

  @doc "Validates an edit (string keys): `{:ok, changes}` or `{:error, {:invalid_fields, errors}}`."
  def changes(_current, params) do
    {changes, errors} =
      {%{}, %{}}
      |> place_id(params)
      |> enabled(params)
      |> milestones(params)

    if errors == %{}, do: {:ok, changes}, else: {:error, {:invalid_fields, errors}}
  end

  defp place_id({changes, errors}, params) do
    case Map.fetch(params, "google_place_id") do
      :error ->
        {changes, errors}

      {:ok, value} when value in [nil, ""] ->
        {Map.put(changes, :google_place_id, nil), errors}

      {:ok, value} when is_binary(value) ->
        value = String.trim(value)

        if Regex.match?(@place_id, value),
          do: {Map.put(changes, :google_place_id, value), errors},
          else: {changes, Map.put(errors, :google_place_id, "invalid")}

      {:ok, _other} ->
        {changes, Map.put(errors, :google_place_id, "invalid")}
    end
  end

  defp enabled({changes, errors}, params) do
    case Map.fetch(params, "enabled") do
      :error -> {changes, errors}
      {:ok, value} when is_boolean(value) -> {Map.put(changes, :enabled, value), errors}
      {:ok, _other} -> {changes, Map.put(errors, :enabled, "invalid")}
    end
  end

  defp milestones({changes, errors}, params) do
    case Map.fetch(params, "milestones") do
      :error ->
        {changes, errors}

      {:ok, list} when is_list(list) ->
        if list != [] and length(list) <= 6 and
             Enum.all?(list, &(is_integer(&1) and &1 in 3..1000)),
           do: {Map.put(changes, :milestones, list |> Enum.uniq() |> Enum.sort()), errors},
           else: {changes, Map.put(errors, :milestones, "invalid")}

      {:ok, _other} ->
        {changes, Map.put(errors, :milestones, "invalid")}
    end
  end

  @doc "Google's «write a review» link for a Place ID."
  def write_review_url(nil), do: nil

  def write_review_url(place_id),
    do: "https://search.google.com/local/writereview?placeid=" <> URI.encode_www_form(place_id)

  @doc "Google's link to read the box's reviews."
  def read_reviews_url(nil), do: nil

  def read_reviews_url(place_id),
    do: "https://www.google.com/maps/place/?q=place_id:" <> URI.encode_www_form(place_id)

  @doc """
  `{:ask, milestone}` or `{:skip, reason}`. `facts`: `active_membership`,
  `member_since`, `attendance_count`, `last_attended_at`; `asks`: this
  member's asks so far; `local_hour`: the hour at the box now.
  """
  def decide(settings, facts, asks, opted_out?, local_hour, now) do
    cond do
      not settings.enabled -> {:skip, :off}
      opted_out? -> {:skip, :opted_out}
      not facts.active_membership -> {:skip, :no_membership}
      not member_long_enough?(facts.member_since, now) -> {:skip, :new_member}
      local_hour not in @day_hours -> {:skip, :night}
      not recently_attended?(facts.last_attended_at, now) -> {:skip, :not_after_class}
      length(asks) >= @max_asks -> {:skip, :asked_enough}
      in_cooldown?(asks, now) -> {:skip, :cooldown}
      true -> milestone(settings.milestones, facts.attendance_count, asks)
    end
  end

  defp member_long_enough?(nil, _now), do: false

  defp member_long_enough?(since, now),
    do: DateTime.diff(now, since, :second) >= @min_member_days * 86_400

  defp recently_attended?(nil, _now), do: false

  defp recently_attended?(at, now),
    do: DateTime.diff(now, at, :second) <= @recent_attendance_days * 86_400

  defp in_cooldown?(asks, now) do
    Enum.any?(asks, &(DateTime.diff(now, &1.shown_at, :second) < @cooldown_days * 86_400))
  end

  defp milestone(milestones, count, asks) do
    asked = MapSet.new(asks, & &1.milestone)

    milestones
    |> Enum.sort(:desc)
    |> Enum.find(&(count >= &1 and count - &1 <= @milestone_slack and &1 not in asked))
    |> case do
      nil -> {:skip, :no_milestone}
      milestone -> {:ask, milestone}
    end
  end

  @doc "The changes of a member's answer, or `{:error, :invalid_review_action}`."
  def respond(%{status: "shown"}, action, now) when action in @actions,
    do: {:ok, %{status: action, responded_at: now}}

  def respond(%{status: status}, action, _now) when action in @actions,
    do: if(status == action, do: {:ok, %{}}, else: {:error, :review_ask_answered})

  def respond(_ask, _action, _now), do: {:error, :invalid_review_action}
end

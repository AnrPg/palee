defmodule Palee.Ranks.Domain.PromotionPolicy do
  @moduledoc """
  Where a person stands on a ladder and what the next step takes (ADR-377).

  * The **current rank** is the latest award that was not withdrawn (by
    date, then by when it was recorded).
  * **Progress** towards the next rank counts classes attended (in the
    ladder's class types, or any class when it names none) and days since
    the current award, against the next rank's requirements; skills are
    the list the coach ticks when promoting. `ready` only tells the coach
    the counted requirements are met: a promotion is always the coach's
    decision, never automatic.
  * **An award** goes up the ladder or adds stripes on the same rank; a
    step down is a withdrawal with a reason, never a new award.
  * **Diploma number**: `R-<year>-<8 hex of the award id>`, unique per box.
  """

  @doc "The current award (not withdrawn), or nil."
  def current(awards) do
    awards
    |> Enum.filter(&is_nil(&1.revoked_at))
    |> Enum.max_by(
      &{Date.to_gregorian_days(&1.awarded_on), DateTime.to_unix(&1.inserted_at, :microsecond)},
      fn -> nil end
    )
  end

  @doc "The rank after `current_rank` in `ranks` (ordered), or the first one."
  def next_rank(ranks, nil), do: List.first(ranks)

  def next_rank(ranks, current_rank) do
    Enum.find(ranks, &(&1.position > current_rank.position))
  end

  @doc """
  Progress to `next`: `%{classes, days, skills, ready}`. `attended` counts
  classes since `since` (the current award's date, nil for never).
  """
  def progress(nil, _since, _attended, _today), do: nil

  def progress(next, since, attended, today) do
    requirements = next.requirements || %{}
    classes_needed = requirements["min_classes"]
    days_needed = requirements["min_days"]
    days = if since, do: Date.diff(today, since), else: nil

    %{
      rank_id: next.id,
      classes: %{done: attended, needed: classes_needed},
      days: %{done: days, needed: days_needed},
      skills: requirements["skills"] || [],
      ready:
        (is_nil(classes_needed) or attended >= classes_needed) and
          (is_nil(days_needed) or (is_integer(days) and days >= days_needed))
    }
  end

  @doc """
  Checks a new award against the current one: `:ok` or
  `{:error, :rank_not_above_current | :too_many_stripes | :award_in_future | :unknown_skills}`.
  """
  def validate_award(rank, stripes, skills, current_rank, current_stripes, awarded_on, today) do
    cond do
      Date.compare(awarded_on, today) == :gt ->
        {:error, :award_in_future}

      stripes > rank.max_stripes ->
        {:error, :too_many_stripes}

      not is_nil(current_rank) and
          (rank.position < current_rank.position or
             (rank.position == current_rank.position and stripes <= current_stripes)) ->
        {:error, :rank_not_above_current}

      not Enum.all?(skills, &(&1 in ((rank.requirements || %{})["skills"] || []))) ->
        {:error, :unknown_skills}

      true ->
        :ok
    end
  end

  @doc "Attendance rows `%{scheduled_at, class_type_id, attendance_status}` that count."
  def count_attended(history, class_type_ids, since) do
    Enum.count(history, fn entry ->
      entry.attendance_status in ["attended"] and
        (class_type_ids == [] or entry[:class_type_id] in class_type_ids) and
        (is_nil(since) or Date.compare(DateTime.to_date(entry.scheduled_at), since) != :lt)
    end)
  end

  @doc "The diploma number of an award."
  def certificate_number(award_id, %Date{year: year}) do
    hex = award_id |> String.replace("-", "") |> String.slice(0, 8) |> String.upcase()
    "R-#{year}-#{hex}"
  end
end

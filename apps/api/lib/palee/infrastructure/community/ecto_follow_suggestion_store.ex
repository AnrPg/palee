defmodule Palee.Infrastructure.Community.EctoFollowSuggestionStore do
  @moduledoc """
  Ecto adapter of «Ίσως γνωρίζεις» (ADR-561): the definer functions of
  migration 20271109150000 and the personal dismissals table.
  """

  @behaviour Palee.Community.Ports.FollowSuggestionStore

  import Ecto.Query

  alias Palee.Community.FollowSuggestionDismissal
  alias Palee.Repo

  @empty_viewer %{following: 0, buddies: 0, clubs: 0, boxes: 0, has_area: false, disciplines: 0}

  @impl true
  def viewer(_context) do
    case Repo.query!(
           "SELECT following, buddies, clubs, boxes, has_area, disciplines FROM palee_follow_suggestion_viewer()"
         ) do
      %{rows: [[following, buddies, clubs, boxes, has_area, disciplines]]} ->
        %{
          following: following,
          buddies: buddies,
          clubs: clubs,
          boxes: boxes,
          has_area: has_area,
          disciplines: disciplines
        }

      %{rows: []} ->
        @empty_viewer
    end
  end

  @impl true
  def candidates(_context, seed, pool, recent_since) do
    %{rows: rows} =
      Repo.query!(
        """
        SELECT user_id, follows_me, box_id, box_name, box_coach, mutual_count, mutual_ids,
          club_id, club_name, shared_disciplines, nearby, via_seed, followers, active_days,
          newcomer, private
        FROM palee_follow_suggestion_candidates($1, $2, $3)
        """,
        [seed && Ecto.UUID.dump!(seed), pool, recent_since]
      )

    Enum.map(rows, fn [
                        id,
                        follows_me,
                        box_id,
                        box_name,
                        box_coach,
                        mutual_count,
                        mutual_ids,
                        club_id,
                        club_name,
                        disciplines,
                        nearby,
                        via_seed,
                        followers,
                        active_days,
                        newcomer,
                        private
                      ] ->
      %{
        user_id: Ecto.UUID.load!(id),
        follows_me: follows_me,
        box_id: load(box_id),
        box_name: box_name,
        box_coach: box_coach,
        mutual_count: mutual_count,
        mutual_ids: Enum.map(mutual_ids || [], &Ecto.UUID.load!/1),
        club_id: load(club_id),
        club_name: club_name,
        shared_disciplines: disciplines || [],
        nearby: nearby,
        via_seed: via_seed,
        followers: followers,
        active_days: active_days,
        newcomer: newcomer,
        private: private
      }
    end)
  end

  @impl true
  def dismiss(_context, user_id, target_id, now) do
    Repo.insert_all(
      FollowSuggestionDismissal,
      [%{user_id: user_id, target_id: target_id, dismissed_at: now}],
      on_conflict: {:replace, [:dismissed_at]},
      conflict_target: [:user_id, :target_id]
    )

    :ok
  end

  @impl true
  def undismiss(_context, user_id, target_id) do
    FollowSuggestionDismissal
    |> where([d], d.user_id == ^user_id and d.target_id == ^target_id)
    |> Repo.delete_all()

    :ok
  end

  @impl true
  def count(_context, reason, event, n) do
    Repo.query!("SELECT palee_follow_suggestion_count($1, $2, $3)", [reason, event, n])
    :ok
  end

  @impl true
  def rates(_context, since) do
    %{rows: rows} =
      Repo.query!("SELECT reason, event, count FROM palee_follow_suggestion_rates($1)", [since])

    Enum.map(rows, fn [reason, event, count] -> %{reason: reason, event: event, count: count} end)
  end

  defp load(nil), do: nil
  defp load(id), do: Ecto.UUID.load!(id)
end

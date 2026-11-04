defmodule Palee.Application.RankSkillNotices do
  @moduledoc """
  The person hears about new skills calmly (ADR-400 follow-up): a coach's
  ticks start a window (`@window_seconds`); when it closes, one
  `rank_skills_checked` notification («2 νέες δεξιότητες», category
  `coach`, so the person's own switch for coach notifications applies)
  tells every tick still standing, and those ticks are marked as told. A
  tick undone inside the window is deleted, so it is never told; when every
  tick was undone nothing is sent. Ticks made at a promotion are not told
  (the promotion is the news).
  """

  require Logger

  alias Palee.Application.Clock
  alias Palee.{Notifications, Ranks}
  alias Palee.Workers.RankSkillNoticeJob

  @window_seconds 3_600

  @doc "Opens (or keeps) the person's window; a no-op without Oban (tests)."
  def schedule(%{organization_id: organization_id}, user_id) do
    RankSkillNoticeJob.schedule(organization_id, user_id, @window_seconds)
  end

  @doc "Tells the person their ticks not yet told, in one notification."
  def deliver(%{organization_id: organization_id} = context, user_id) do
    {checks, notice} =
      Ranks.with_context(context, fn ->
        checks = Ranks.list_unnotified_checks(user_id)

        ranks =
          Ranks.list_ladders() |> Enum.flat_map(& &1.ranks) |> Map.new(&{&1.id, &1})

        {checks, Ranks.skill_notice(checks, ranks)}
      end)

    if notice do
      result =
        Notifications.dispatch_event(:rank_skills_checked, %{
          user_id: user_id,
          organization_id: organization_id,
          count: notice.count,
          rank_name: notice.rank_name,
          ranks: notice.ranks,
          dedupe_key: "rank_skills_checked:#{user_id}:#{Enum.min_by(checks, & &1.id).id}"
        })

      case result do
        {:error, reason} ->
          Logger.warning("rank_skill_notice_failed reason=#{inspect(reason)}")

        _sent ->
          :ok
      end
    end

    Ranks.with_context(context, fn ->
      Ranks.mark_checks_notified(Enum.map(checks, & &1.id), Clock.now())
    end)
  end
end

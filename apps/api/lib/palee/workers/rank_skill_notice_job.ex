defmodule Palee.Workers.RankSkillNoticeJob do
  @moduledoc """
  Closes a person's window of new skill ticks and sends the one grouped
  notice (ADR-400 follow-up, `RankSkillNotices`). One scheduled job per
  person and box at a time: more ticks inside the window join it.
  """

  use Oban.Worker,
    queue: :notifications,
    max_attempts: 5,
    unique: [keys: [:organization_id, :user_id], period: :infinity, states: [:scheduled]]

  require Logger

  alias Palee.Application.{OwnershipKeys, RankSkillNotices}

  @doc "Schedules the notice `seconds` from now unless one is already waiting."
  def schedule(organization_id, user_id, seconds) do
    if Oban.whereis(Oban) do
      %{organization_id: organization_id, user_id: user_id}
      |> new(schedule_in: seconds)
      |> Oban.insert()
      |> case do
        {:ok, _job} -> :ok
        {:error, reason} -> Logger.warning("rank_skill_notice_schedule_failed #{inspect(reason)}")
      end
    end

    :ok
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    with {:ok, %{"organization_id" => organization_id, "user_id" => user_id}} <-
           OwnershipKeys.require_tenant_args(args) do
      RankSkillNotices.deliver(%{organization_id: organization_id}, user_id)
    end
  end
end

defmodule Palee.Workers.RefreshMemberRisksJob do
  @moduledoc """
  ADR-347: once a day, scores every box's active clients again («Σε
  κίνδυνο») and announces members whose risk became high, for the win-back
  recipe. Idempotent: a second run the same day changes nothing new.
  """

  use Oban.Worker, queue: :analytics, max_attempts: 3, unique: [period: 3_600]

  require Logger

  alias Palee.Application.Retention.MembersAtRisk
  alias Palee.{Organizations, Retention}

  @impl Oban.Worker
  def perform(_job) do
    Organizations.list_active_organizations_for_system()
    |> Enum.each(fn %{organization: organization} -> run(%{organization_id: organization.id}) end)

    :ok
  end

  @doc "Runs for one box (`context` carries its id)."
  def run(context, now \\ Retention.now()) do
    MembersAtRisk.refresh(context, now)
  rescue
    error ->
      Logger.error(
        "member risk refresh failed for #{context.organization_id}: #{Exception.message(error)}"
      )

      %{}
  end
end

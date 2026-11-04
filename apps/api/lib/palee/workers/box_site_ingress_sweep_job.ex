defmodule Palee.Workers.BoxSiteIngressSweepJob do
  @moduledoc """
  ADR-398, nightly (01:15 UTC): removes the Ingresses of custom hosts no
  box has any more, recreates missing ones and rereads active certificates
  (`SiteIngresses.sweep/0`).
  """

  use Oban.Worker, queue: :box_site, max_attempts: 1, unique: [period: 600]

  require Logger

  alias Palee.Application.BoxSite.SiteIngresses

  @impl Oban.Worker
  def perform(_job) do
    case SiteIngresses.sweep() do
      {:ok, %{removed: removed, restored: restored, certificates: changed}}
      when removed + restored + changed > 0 ->
        Logger.info(
          "site ingress sweep: #{removed} removed, #{restored} restored, " <>
            "#{changed} certificates changed"
        )

      {:ok, _counts} ->
        :ok

      {:error, reason} ->
        Logger.warning("site ingress sweep skipped: #{inspect(reason)}")
    end

    :ok
  end
end

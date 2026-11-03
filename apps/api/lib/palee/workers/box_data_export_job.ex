defmodule Palee.Workers.BoxDataExportJob do
  @moduledoc """
  ADR-365: builds one copy of a box's data in the owner's tenant session.
  Retried while storage is briefly unavailable; the last attempt marks the
  export failed so the owner can ask again.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [period: 3_600, fields: [:worker, :args], keys: [:export_id]]

  alias Palee.Application.BoxDataExports

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"organization_id" => organization_id, "export_id" => export_id} = args,
        attempt: attempt,
        max_attempts: max_attempts
      }) do
    case BoxDataExports.build(args, DateTime.utc_now()) do
      {:ok, _outcome} ->
        :ok

      {:error, reason} ->
        if attempt >= max_attempts, do: BoxDataExports.fail(organization_id, export_id, reason)
        {:error, reason}
    end
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(15)
end

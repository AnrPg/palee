defmodule Palee.Application.BoxSite.SiteOutbox do
  @moduledoc """
  ADR-353/354: hands website submissions to the leads context through
  `BoxSite.Ports.LeadIntake`, sends the optional Conversions API events and
  applies retention (failed submissions cleared after 30 days, consent log
  rows deleted after 2 years). Claims are row-locked, so overlapping runs
  are safe.
  """

  require Logger

  alias Palee.BoxSite
  alias Palee.Workers.BoxSiteJob

  @batch 20

  @doc """
  Runs the box's outbox soon: a job when background jobs run, inline
  otherwise (tests, one-off tasks).
  """
  def schedule(%{organization_id: organization_id} = context) do
    if Application.get_env(:palee, :start_oban, true) do
      %{"organization_id" => organization_id} |> BoxSiteJob.new() |> Oban.insert()
      :ok
    else
      run(context, BoxSite.clock().now())
      :ok
    end
  end

  @doc "One pass over the box's outbox: `%{delivered, conversions, redacted, expired}`."
  def run(context, now) do
    %{
      delivered: deliver(context, now),
      conversions: send_conversions(context, now),
      redacted: BoxSite.redact_failed(context, now),
      expired: BoxSite.expire_consents(context, now)
    }
  end

  defp deliver(context, now) do
    intake = BoxSite.lead_intake()

    context
    |> BoxSite.claim_submissions(now, @batch)
    |> Enum.count(fn submission ->
      result = safe_submit(intake, context, BoxSite.intake(submission))
      changes = BoxSite.after_delivery(result, submission, now)
      {:ok, _row} = BoxSite.finish_submission(context, submission.id, changes)
      match?({:ok, _}, result)
    end)
  end

  defp safe_submit(intake, context, payload) do
    case intake.submit(context, payload) do
      {:ok, %{lead_id: _}} = ok -> ok
      {:error, {kind, _reason}} = error when kind in [:rejected, :transient] -> error
      other -> {:error, {:transient, {:unexpected, other}}}
    end
  rescue
    error ->
      Logger.error("lead intake failed: #{Exception.message(error)}")
      {:error, {:transient, :intake_crashed}}
  end

  defp send_conversions(context, now) do
    case BoxSite.claim_conversions(context, now, @batch) do
      [] ->
        0

      claimed ->
        settings = BoxSite.settings(context)
        token = BoxSite.conversions_api_token(context)

        Enum.count(claimed, fn submission ->
          result = convert(settings, token, submission)
          changes = BoxSite.after_conversion(result, submission.conversion_attempts, now)
          {:ok, _row} = BoxSite.finish_submission(context, submission.id, changes)
          result == :ok
        end)
    end
  end

  # Turned off or token removed since: the event is dropped, never sent.
  defp convert(%{conversions_api_enabled: true, meta_pixel_id: pixel}, token, submission)
       when is_binary(pixel) and is_binary(token) and is_map(submission.conversion_payload) do
    BoxSite.conversions_api().send_event(pixel, token, submission.conversion_payload)
  end

  defp convert(_settings, _token, _submission), do: {:error, {:rejected, :conversions_off}}
end

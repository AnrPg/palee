defmodule Palee.Application.Automations.AutomationReactions do
  @moduledoc """
  ADR-346: the event-driven recipes, as domain-event handlers.

    * `:membership_activated` - «Καλωσόρισμα» to the new box member;
    * `:attendance_recorded` of a trial seat («Ήρθε») - «Μετά το
      δοκιμαστικό» to the trial visitor;
    * `:lead_moved` to `trial` by staff - «Μετά το δοκιμαστικό» to a lead
      without a profile (by email);
    * `:member_at_risk` (ADR-347) - «Επαναφορά» to a box member whose risk
      became high.

  Each one only queues (`ScheduleAutomation`): the outbox decides again at
  send time, and the trigger reference makes replays harmless.
  """

  @behaviour Palee.DomainEvents.Handler

  require Logger

  alias Palee.Application.Automations.ScheduleAutomation
  alias Palee.{Automations, Trials}

  @impl true
  def handle_event(:membership_activated, %{organization_id: org, user_id: user} = event)
      when is_binary(org) and is_binary(user) do
    schedule(org, "welcome", %{user_id: user}, "welcome:" <> user, event)
  end

  def handle_event(
        :attendance_recorded,
        %{organization_id: org, user_id: user, booking_id: booking, status: "attended"} = event
      )
      when is_binary(org) and is_binary(user) and is_binary(booking) do
    if Trials.get_request_by_booking(%{organization_id: org}, booking) do
      schedule(org, "trial_follow_up", %{user_id: user}, "trial:" <> booking, event)
    end

    :ok
  end

  def handle_event(:lead_moved, %{organization_id: org, lead_id: lead, to: "trial"} = event)
      when is_binary(org) and is_binary(lead) do
    schedule(org, "trial_follow_up", %{lead_id: lead}, "trial_lead:" <> lead, event)
  end

  def handle_event(:member_at_risk, %{organization_id: org, user_id: user} = event)
      when is_binary(org) and is_binary(user) do
    since = event |> Map.get(:level_since, event[:at]) |> ref_date()
    schedule(org, "win_back", %{user_id: user}, "win_back:#{user}:#{since}", event)
  end

  def handle_event(_name, _event), do: :ok

  defp schedule(org, recipe, recipient, ref, event) do
    case ScheduleAutomation.call(
           %{organization_id: org},
           recipe,
           recipient,
           ref,
           event[:at] || Automations.now()
         ) do
      {:ok, _how} ->
        :ok

      {:error, reason} ->
        Logger.warning("automation_schedule_failed recipe=#{recipe} reason=#{inspect(reason)}")
        :ok
    end
  end

  defp ref_date(%DateTime{} = at), do: Date.to_iso8601(DateTime.to_date(at))
  defp ref_date(_other), do: "now"
end

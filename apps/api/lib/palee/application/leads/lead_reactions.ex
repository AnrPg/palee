defmodule Palee.Application.Leads.LeadReactions do
  @moduledoc """
  How leads follow the rest of the box (ADR-344), as domain-event handlers:

    * a person who becomes an active box member converts their open leads
      at this box (matched by profile, or by the profile's email), keeping
      the lead's history (`converted`, `via: membership_activated`);
    * a person who comes to a trial class moves their `new` lead to
      `trial`.

  Each reaction re-reads the leads and skips what does not apply, so
  replays change nothing.
  """

  @behaviour Palee.DomainEvents.Handler

  require Logger

  alias Palee.{Identity, Leads, Trials}

  @impl true
  def handle_event(:membership_activated, %{organization_id: org_id, user_id: user_id} = event)
      when is_binary(org_id) and is_binary(user_id) do
    context = %{organization_id: org_id}
    now = event[:at] || Leads.now()

    for lead <- Leads.open_for_person(context, user_id, email(user_id)) do
      convert(context, lead, user_id, now)
    end

    :ok
  end

  def handle_event(
        :attendance_recorded,
        %{organization_id: org_id, user_id: user_id, booking_id: booking_id, status: "attended"} =
          event
      )
      when is_binary(org_id) and is_binary(user_id) and is_binary(booking_id) do
    context = %{organization_id: org_id}
    now = event[:at] || Leads.now()

    if Trials.get_request_by_booking(context, booking_id) do
      for %{stage: "new"} = lead <- Leads.open_for_person(context, user_id, email(user_id)) do
        to_trial(context, lead, now)
      end
    end

    :ok
  end

  def handle_event(_name, _event), do: :ok

  @doc "Converts one lead to the box member `user_id` with a history line (`via`)."
  def convert(context, lead, user_id, now, via \\ "membership_activated", actor_id \\ nil) do
    Leads.transaction(context, fn ->
      with %{} = locked <- Leads.get_for_update(context, lead.id) || {:error, :not_found},
           {:ok, changes} <- Leads.convert(locked, user_id, now),
           {:ok, converted} <- Leads.update(context, locked, changes),
           {:ok, _event} <-
             Leads.add_event(context, %{
               lead_id: converted.id,
               kind: "converted",
               actor_id: actor_id,
               at: now,
               data: %{"user_id" => user_id, "via" => via, "from" => locked.stage}
             }) do
        {:ok, converted}
      end
    end)
    |> log_failure("convert", lead.id)
  end

  defp to_trial(context, lead, now) do
    Leads.transaction(context, fn ->
      with {:ok, changes} <- Leads.move(lead, "trial", now, []),
           {:ok, moved} <- Leads.update(context, lead, changes),
           {:ok, _event} <-
             Leads.add_event(context, %{
               lead_id: moved.id,
               kind: "stage_changed",
               at: now,
               data: %{"from" => lead.stage, "to" => "trial", "via" => "trial_attended"}
             }) do
        {:ok, moved}
      end
    end)
    |> log_failure("trial", lead.id)
  end

  defp email(user_id) do
    case Identity.find_by_id(user_id) do
      %{email: email} when is_binary(email) -> email
      _none -> nil
    end
  end

  defp log_failure({:error, :lead_converted}, _step, _id), do: {:error, :lead_converted}

  defp log_failure({:error, reason} = error, step, id) do
    Logger.warning("lead_reaction_failed step=#{step} lead=#{id} reason=#{inspect(reason)}")
    error
  end

  defp log_failure(ok, _step, _id), do: ok
end

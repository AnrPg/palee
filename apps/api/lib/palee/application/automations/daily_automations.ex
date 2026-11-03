defmodule Palee.Application.Automations.DailyAutomations do
  @moduledoc """
  ADR-346: the recipes that look at the calendar, once a day per box after
  its send hour (10:00 on the box's clock unless the box chose another):

    * «Σου λείψαμε» - box members whose last class was `days_absent` days
      ago or more (once per absence: the reference is the last visit);
    * «Υπενθύμιση ανανέωσης» - subscription packages that end within
      `days_before` days and will not renew by themselves (once per
      package period);
    * «Χρόνια πολλά» - box members who shared their birthday with the box
      (once a year; 29 February is greeted on 28 February in other years).

  The hourly job calls `run/2` for every box; before the send hour, or with
  every daily recipe off, it does nothing. Running twice queues nothing new.
  """

  require Logger

  alias Palee.Application.Automations.ScheduleAutomation
  alias Palee.{Automations, Organizations}
  alias Palee.TimeZones.ZonedTime

  @doc "Queues today's daily messages of one box. Answers how many were queued."
  def run(%{organization_id: organization_id} = context, now \\ Automations.now()) do
    zone = Organizations.organization_timezone(organization_id)
    today = ZonedTime.local_date(now, zone)
    local_hour = ZonedTime.local(now, zone).hour
    automations = context |> Automations.list_automations() |> Map.new(&{&1.recipe, &1})

    Automations.daily_recipes()
    |> Enum.filter(&match?(%{enabled: true}, Map.get(automations, &1.key)))
    |> Enum.map(fn recipe ->
      settings = Automations.settings(recipe, automations[recipe.key].settings)

      if local_hour >= settings["send_hour"] do
        at = Automations.at_local_hour(today, settings["send_hour"], zone)
        at = if DateTime.compare(at, now) == :lt, do: now, else: at
        scan(context, recipe.key, settings, today, at)
      else
        0
      end
    end)
    |> Enum.sum()
  end

  defp scan(context, "missed_classes" = recipe, settings, today, at) do
    days = settings["days_absent"]

    context
    |> Automations.absent_members(today, days)
    |> queue(context, recipe, at, fn %{user_id: user, last_visit_on: last} ->
      {%{user_id: user}, "missed:#{user}:#{last}",
       %{"days" => Date.diff(today, last), "last_visit_on" => Date.to_iso8601(last)}}
    end)
  end

  defp scan(context, "renewal_reminder" = recipe, settings, today, at) do
    context
    |> Automations.ending_subscriptions(today, settings["days_before"])
    |> queue(context, recipe, at, fn row ->
      {%{user_id: row.user_id}, "renewal:#{row.subscription_id}:#{row.ends_on}",
       %{"package" => row.package_name, "ends_on" => Date.to_iso8601(row.ends_on)}}
    end)
  end

  defp scan(context, "birthday" = recipe, _settings, today, at) do
    days =
      if today.month == 2 and today.day == 28 and not Date.leap_year?(today),
        do: [{2, 28}, {2, 29}],
        else: [{today.month, today.day}]

    days
    |> Enum.flat_map(fn {month, day} -> Automations.birthdays(context, month, day) end)
    |> Enum.uniq()
    |> queue(context, recipe, at, fn user ->
      {%{user_id: user}, "birthday:#{user}:#{today.year}", %{}}
    end)
  end

  defp scan(_context, _recipe, _settings, _today, _at), do: 0

  defp queue(rows, context, recipe, at, build) do
    Enum.count(rows, fn row ->
      {recipient, ref, data} = build.(row)

      case ScheduleAutomation.call(context, recipe, recipient, ref, at, data) do
        {:ok, :queued} ->
          true

        {:ok, _other} ->
          false

        {:error, reason} ->
          Logger.warning("daily_automation_failed recipe=#{recipe} reason=#{inspect(reason)}")
          false
      end
    end)
  end
end

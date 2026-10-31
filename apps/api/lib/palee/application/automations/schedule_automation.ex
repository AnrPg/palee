defmodule Palee.Application.Automations.ScheduleAutomation do
  @moduledoc """
  ADR-346: a recipe decided to send something. When the box has the recipe
  on, the message is queued in the outbox, due after the recipe's delay and
  outside the box's quiet hours. Idempotent per `trigger_ref`: the same
  trigger twice (a replayed event, a scan run again) queues nothing more.

  `recipient` is `%{user_id: id}` (a profile) or `%{lead_id: id}`; `data`
  holds what the text needs from the trigger (`days`, `package`...).
  Answers `{:ok, :queued | :existing | :off}` or `{:error, reason}`.
  """

  alias Palee.{Automations, Organizations}

  def call(context, recipe_key, recipient, trigger_ref, at, data \\ %{})

  def call(
        %{organization_id: organization_id} = context,
        recipe_key,
        recipient,
        trigger_ref,
        at,
        data
      )
      when is_binary(organization_id) and is_binary(trigger_ref) do
    with {:ok, recipe} <- Automations.fetch_recipe(recipe_key),
         %{enabled: true} = automation <- Automations.get_automation(context, recipe_key) do
      settings = Automations.settings(recipe, automation.settings)
      delay = automation.delay_minutes || recipe.delay_minutes
      zone = Organizations.organization_timezone(organization_id)

      context
      |> Automations.enqueue(%{
        recipe: recipe_key,
        user_id: recipient[:user_id],
        lead_id: recipient[:lead_id],
        trigger_ref: trigger_ref,
        data: data,
        due_at: Automations.due_at(at, delay, settings, zone)
      })
      |> case do
        {:ok, _delivery, :created} -> {:ok, :queued}
        {:ok, _delivery, :existing} -> {:ok, :existing}
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, reason} -> {:error, reason}
      _off -> {:ok, :off}
    end
  end
end

defmodule Palee.Automations do
  @moduledoc """
  The Automations bounded context (ADR-346): ready recipes a box switches
  on, the outbox of the messages they decide to send, and box members'
  choices about them. Not a workflow builder.

  Channels are adapters of `Palee.Automations.Ports.Channel`, registered by
  name in `config :palee, :automation_channels` (`in_app`, `email` today;
  the SMS/Viber/WhatsApp channels of CP-C3 join the same map).
  """

  alias Palee.Automations.{AudienceReader, AutomationStore}
  alias Palee.Automations.Domain.{DeliveryPolicy, QuietHours, RecipeCatalog, RecipeTexts}

  # A `sending` row older than this lost its worker and is claimed again.
  @claim_timeout_seconds 600

  def claim_timeout_seconds, do: @claim_timeout_seconds

  @doc "The configured clock (`Automations.Ports.Clock`)."
  def clock,
    do: Application.get_env(:palee, :automations_clock, Palee.Infrastructure.Automations.SystemClock)

  def now, do: clock().now()

  @doc "Channel name => adapter module, as configured."
  def channels, do: Application.get_env(:palee, :automation_channels, %{})

  @doc "The adapter of a channel, or nil when this deployment has none."
  def channel(name), do: Map.get(channels(), name)

  @doc "The channel names a box may pick from."
  def channel_names, do: channels() |> Map.keys() |> Enum.sort()

  defdelegate list_automations(context), to: AutomationStore
  defdelegate get_automation(context, recipe), to: AutomationStore
  defdelegate put_automation(context, recipe, attrs), to: AutomationStore
  defdelegate enqueue(context, attrs), to: AutomationStore
  defdelegate finish(context, id, changes), to: AutomationStore
  defdelegate list_deliveries(context, filters), to: AutomationStore
  defdelegate delivery_stats(context, since), to: AutomationStore
  defdelegate cancel_pending(context, filters), to: AutomationStore
  defdelegate get_preference(context, user_id), to: AutomationStore
  defdelegate put_preference(context, user_id, attrs), to: AutomationStore
  defdelegate birthdays(context, month, day), to: AutomationStore
  defdelegate absent_members(context, today, days), to: AudienceReader
  defdelegate ending_subscriptions(context, today, days), to: AudienceReader

  def claim_due(context, now, limit),
    do: AutomationStore.claim_due(context, now, limit, @claim_timeout_seconds)

  defdelegate recipes(), to: RecipeCatalog, as: :all
  defdelegate recipe_keys(), to: RecipeCatalog, as: :keys
  defdelegate fetch_recipe(key), to: RecipeCatalog, as: :fetch
  defdelegate recipes_for_event(name), to: RecipeCatalog, as: :for_event
  defdelegate daily_recipes(), to: RecipeCatalog, as: :daily
  defdelegate settings(recipe, stored), to: RecipeCatalog
  defdelegate validate_settings(recipe, params), to: RecipeCatalog
  defdelegate default_text(recipe, locale), to: RecipeTexts, as: :default
  defdelegate validate_text(text, field), to: RecipeTexts, as: :validate
  defdelegate render(text, vars), to: RecipeTexts
  defdelegate placeholders(), to: RecipeTexts
  defdelegate decide(facts), to: DeliveryPolicy
  defdelegate due_at(at, delay_minutes, settings, time_zone), to: DeliveryPolicy
  defdelegate after_failure(attempts, now), to: DeliveryPolicy
  defdelegate at_local_hour(date, hour, time_zone), to: QuietHours

  def tenant_data_policy, do: Palee.Automations.Domain.TenantDataPolicy.policy()

  def tenant_data_inventory(context),
    do: Palee.TenantData.TableStore.inventory(tenant_data_policy(), context)

  def export_tenant_data(context, mode \\ :full),
    do: Palee.TenantData.TableStore.export(tenant_data_policy(), context, mode)

  def purge_tenant_data(context),
    do: Palee.TenantData.TableStore.purge(tenant_data_policy(), context)
end

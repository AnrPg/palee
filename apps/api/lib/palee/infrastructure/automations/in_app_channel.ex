defmodule Palee.Infrastructure.Automations.InAppChannel do
  @moduledoc """
  ADR-346: `in_app` - an automatic message in the person's bell (and push,
  per their choices of ADR-199, category «Μηνύματα»). Reaches only people
  with a Palee profile; leads without one are skipped to the next channel.
  Deduplicated per delivery, so a retry never shows it twice.
  """

  @behaviour Palee.Automations.Ports.Channel

  alias Palee.Notifications

  @impl true
  def channel, do: "in_app"

  @impl true
  def reachable?(%{user_id: user_id}) when is_binary(user_id), do: true
  def reachable?(_recipient), do: false

  @impl true
  def deliver(%{recipient: %{user_id: user_id}} = message) when is_binary(user_id) do
    case Notifications.process_event("box_automation", %{
           user_id: user_id,
           organization_id: message.organization_id,
           title: message.subject,
           body: message.body,
           url: Map.get(message, :url),
           recipe: message.recipe,
           dedupe_key: "box_automation:" <> message.delivery_id
         }) do
      {:ok, notification} -> {:ok, notification.id}
      :ok -> {:ok, nil}
      # The bell row was written; only its push failed to queue.
      {:error, {:push_enqueue_failed, notification, _reason}} -> {:ok, notification.id}
      {:error, reason} -> {:error, {:transient, reason}}
    end
  end

  def deliver(_message), do: {:error, {:permanent, :no_profile}}
end

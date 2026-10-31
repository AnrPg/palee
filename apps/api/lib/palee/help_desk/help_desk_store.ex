defmodule Palee.HelpDesk.HelpDeskStore do
  @moduledoc false
  @behaviour Palee.HelpDesk.Ports.HelpDeskStore

  alias Palee.Infrastructure.Tenancy.RepoContext

  defp adapter, do: Application.fetch_env!(:palee, :help_desk_store)

  defp tenant_call(context, function, args) do
    RepoContext.run(context, fn -> apply(adapter(), function, [context | args]) end)
  end

  # The vendor's own session (no box): the tickets policy admits the team.
  defp vendor_call(%{user_id: user_id} = context, function, args) when is_binary(user_id) do
    RepoContext.run(%{user_id: user_id}, fn -> apply(adapter(), function, [context | args]) end)
  end

  @impl true
  def create_conversation(context, attrs), do: tenant_call(context, :create_conversation, [attrs])
  @impl true
  def get_conversation(context, id), do: tenant_call(context, :get_conversation, [id])
  @impl true
  def list_conversations(context, user_id),
    do: tenant_call(context, :list_conversations, [user_id])

  @impl true
  def update_conversation(context, id, changes),
    do: tenant_call(context, :update_conversation, [id, changes])

  @impl true
  def add_message(context, attrs), do: tenant_call(context, :add_message, [attrs])
  @impl true
  def list_messages(context, id), do: tenant_call(context, :list_messages, [id])
  @impl true
  def count_person_messages_since(context, user_id, since),
    do: tenant_call(context, :count_person_messages_since, [user_id, since])

  @impl true
  def create_ticket(context, attrs), do: tenant_call(context, :create_ticket, [attrs])
  @impl true
  def ticket_for_conversation(context, id), do: tenant_call(context, :ticket_for_conversation, [id])
  @impl true
  def update_ticket(context, id, changes), do: tenant_call(context, :update_ticket, [id, changes])
  @impl true
  def list_tickets(vendor, filters), do: vendor_call(vendor, :list_tickets, [filters])
  @impl true
  def get_ticket(vendor, id), do: vendor_call(vendor, :get_ticket, [id])
end

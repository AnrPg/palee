defmodule Palee.Channels.ChannelStore do
  @moduledoc false
  @behaviour Palee.Channels.Ports.ChannelStore

  alias Palee.Infrastructure.Tenancy.RepoContext

  defp adapter, do: Application.fetch_env!(:palee, :channel_store)

  defp tenant_call(context, function, args) do
    RepoContext.run(context, fn -> apply(adapter(), function, [context | args]) end)
  end

  @impl true
  def transaction(context, fun),
    do: tenant_call(context, :transaction, [fun])

  @impl true
  def get_connection(context),
    do: tenant_call(context, :get_connection, [])

  @impl true
  def save_connection(context, attrs),
    do: tenant_call(context, :save_connection, [attrs])

  @impl true
  def get_contact(context, id),
    do: tenant_call(context, :get_contact, [id])

  @impl true
  def find_contact(context, person),
    do: tenant_call(context, :find_contact, [person])

  @impl true
  def save_contact(context, person, attrs),
    do: tenant_call(context, :save_contact, [person, attrs])

  @impl true
  def delete_contact(context, id),
    do: tenant_call(context, :delete_contact, [id])

  @impl true
  def contacts_by_phone(context, phone),
    do: tenant_call(context, :contacts_by_phone, [phone])

  @impl true
  def list_contacts(context, filters),
    do: tenant_call(context, :list_contacts, [filters])

  @impl true
  def list_consents(context, contact_ids),
    do: tenant_call(context, :list_consents, [contact_ids])

  @impl true
  def put_consent(context, contact_id, channel, purpose, attrs),
    do: tenant_call(context, :put_consent, [contact_id, channel, purpose, attrs])

  @impl true
  def list_templates(context, key),
    do: tenant_call(context, :list_templates, [key])

  @impl true
  def save_template(context, attrs),
    do: tenant_call(context, :save_template, [attrs])

  @impl true
  def delete_template(context, key, locale, channel),
    do: tenant_call(context, :delete_template, [key, locale, channel])

  @impl true
  def insert_message(context, attrs),
    do: tenant_call(context, :insert_message, [attrs])

  @impl true
  def get_message(context, id),
    do: tenant_call(context, :get_message, [id])

  @impl true
  def get_message_by_key(context, key),
    do: tenant_call(context, :get_message_by_key, [key])

  @impl true
  def get_message_by_provider_id(context, provider, provider_message_id),
    do: tenant_call(context, :get_message_by_provider_id, [provider, provider_message_id])

  @impl true
  def claim(context, which, now, limit),
    do: tenant_call(context, :claim, [which, now, limit])

  @impl true
  def update_message(context, id, changes, event),
    do: tenant_call(context, :update_message, [id, changes, event])

  @impl true
  def record_event(context, attrs),
    do: tenant_call(context, :record_event, [attrs])

  @impl true
  def list_messages(context, filters),
    do: tenant_call(context, :list_messages, [filters])

  @impl true
  def list_events(context, id),
    do: tenant_call(context, :list_events, [id])

  @impl true
  def spend(context, from, to),
    do: tenant_call(context, :spend, [from, to])
end

defmodule Palee.Status.StatusStore do
  @moduledoc "Facade over the configured status page store (ADR-364)."

  @behaviour Palee.Status.Ports.StatusStore

  @impl true
  def record_probe(results, now), do: impl().record_probe(results, now)
  @impl true
  def list_component_states, do: impl().list_component_states()
  @impl true
  def list_samples(first, last), do: impl().list_samples(first, last)
  @impl true
  def delete_samples_before(day), do: impl().delete_samples_before(day)
  @impl true
  def list_incidents(since), do: impl().list_incidents(since)
  @impl true
  def get_incident(id), do: impl().get_incident(id)
  @impl true
  def create_incident(attrs, update), do: impl().create_incident(attrs, update)
  @impl true
  def add_update(id, author_id, fun), do: impl().add_update(id, author_id, fun)
  @impl true
  def edit_incident(id, changes), do: impl().edit_incident(id, changes)
  @impl true
  def get_update(id), do: impl().get_update(id)
  @impl true
  def get_subscriber_by_digest(digest), do: impl().get_subscriber_by_digest(digest)
  @impl true
  def get_subscriber(id), do: impl().get_subscriber(id)
  @impl true
  def create_subscriber(attrs), do: impl().create_subscriber(attrs)
  @impl true
  def refresh_subscriber(subscriber, attrs), do: impl().refresh_subscriber(subscriber, attrs)
  @impl true
  def confirm_subscriber(digest, not_before, now),
    do: impl().confirm_subscriber(digest, not_before, now)
  @impl true
  def delete_subscriber(id), do: impl().delete_subscriber(id)
  @impl true
  def delete_unconfirmed_before(cutoff), do: impl().delete_unconfirmed_before(cutoff)
  @impl true
  def list_confirmed_subscribers(after_id, limit),
    do: impl().list_confirmed_subscribers(after_id, limit)

  @impl true
  def count_subscribers, do: impl().count_subscribers()

  defp impl,
    do: Application.get_env(:palee, :status_store, Palee.Infrastructure.Status.EctoStatusStore)
end

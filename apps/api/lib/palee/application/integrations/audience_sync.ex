defmodule Palee.Application.Integrations.AudienceSync do
  @moduledoc """
  Keeps the box's Mailchimp/Brevo list in step with members' consent
  (ADR-380): subscribes members who said yes (email and first name only)
  and unsubscribes those who took it back, left the box or have no email.

  Runs after a consent change or «Συγχρονισμός τώρα» (a job per box), and
  hourly for boxes that asked for it or were last synced a day ago. The
  connection is leased, so two runs never overlap. A refused key stops the
  run and marks the connection invalid for the owner to fix.
  """

  require Logger

  alias Palee.{Identity, Integrations, Organizations}
  alias Palee.Integrations.Domain.AudienceSyncPlan
  alias Palee.Workers.AudienceSyncJob

  @daily_seconds 86_400

  @doc "Syncs the box soon (inline without background jobs)."
  def schedule(%{organization_id: organization_id} = context) do
    if Application.get_env(:palee, :start_oban, true) do
      %{"organization_id" => organization_id} |> AudienceSyncJob.new() |> Oban.insert()
      :ok
    else
      _result = run(context)
      :ok
    end
  end

  @doc """
  One sync run: `{:ok, %{subscribed, unsubscribed, failed}}`, `{:ok,
  :busy}` when another run holds the connection, or `{:error,
  :audience_not_connected}`.
  """
  def run(context, now \\ DateTime.utc_now()) do
    case Integrations.connection_for_sync(context) do
      nil ->
        {:error, :audience_not_connected}

      _connection ->
        case Integrations.claim_sync(context, now) do
          nil -> {:ok, :busy}
          connection -> sync(context, connection, now)
        end
    end
  end

  @doc """
  Account deletion (ADR-380, GDPR art. 17): before the account and its
  rows go, every box list the person is subscribed to is told, by the
  address that only the account still knows. Best effort: a provider that
  does not answer is logged, never blocks the deletion.
  """
  def forget_person(%{id: user_id, email: email}) when is_binary(user_id) and is_binary(email) do
    [user_id]
    |> Organizations.list_membership_organization_ids()
    |> Map.get(user_id, [])
    |> Enum.each(&forget_in(%{organization_id: &1}, user_id, email))
  end

  def forget_person(_profile), do: :ok

  defp forget_in(context, user_id, email) do
    with %{} = connection <- Integrations.connection_for_sync(context),
         true <-
           context
           |> Integrations.audience_members(connection.id)
           |> Enum.any?(&(&1.user_id == user_id and &1.status == "subscribed")),
         {:error, reason} <-
           Integrations.audience_provider(connection.provider).unsubscribe(connection, email) do
      Logger.warning("audience unsubscribe on account deletion failed: #{inspect(reason)}")
    end

    :ok
  rescue
    error -> Logger.error("audience unsubscribe on account deletion: #{Exception.message(error)}")
  end

  @doc "Whether the box's list is due a sync (asked for, or a day since the last)."
  def due?(%{sync_requested_at: requested, last_synced_at: synced}, now) do
    cond do
      requested && (is_nil(synced) or DateTime.compare(requested, synced) == :gt) -> true
      is_nil(synced) -> true
      true -> DateTime.diff(now, synced) >= @daily_seconds
    end
  end

  def due?(_connection, _now), do: false

  @doc "The hourly sweep: every box with a connection that is due."
  def sweep(organization_ids, now \\ DateTime.utc_now()) do
    Enum.each(organization_ids, fn organization_id ->
      context = %{organization_id: organization_id}

      try do
        if due?(Integrations.connection(context), now), do: run(context, now)
      rescue
        error ->
          Logger.error("audience sync failed for #{organization_id}: #{Exception.message(error)}")
      end
    end)
  end

  defp sync(context, connection, now) do
    adapter = Integrations.audience_provider(connection.provider)
    wanted = wanted_contacts(context)
    synced = Integrations.audience_members(context, connection.id)
    plan = AudienceSyncPlan.plan(wanted, synced)
    emails = Map.new(wanted, &{&1.user_id, &1.email})

    {counts, error} =
      {%{subscribed: 0, unsubscribed: 0, failed: 0}, nil}
      |> subscribe_all(plan.subscribe, context, connection, adapter, now)
      |> unsubscribe_all(plan.unsubscribe, emails, context, connection, adapter, now)

    :ok = Integrations.finish_sync(context, now, error)
    if match?({:unauthorized, _}, error), do: {:error, :audience_unauthorized}, else: {:ok, counts}
  end

  defp subscribe_all(acc, contacts, context, connection, adapter, now) do
    Enum.reduce_while(contacts, acc, fn contact, {counts, error} ->
      result = adapter.subscribe(connection, contact)
      record(context, connection, contact.user_id, contact.email, "subscribed", result, now)
      step(result, :subscribed, counts, error)
    end)
  end

  # An unsubscribe needs the address: a member who still has one is told by
  # it; one whose account is gone was removed with it (ON DELETE CASCADE).
  defp unsubscribe_all({counts, {:unauthorized, _} = error}, _rows, _emails, _context, _connection, _adapter, _now),
    do: {counts, error}

  defp unsubscribe_all(acc, rows, emails, context, connection, adapter, now) do
    accounts =
      rows |> Enum.map(& &1.user_id) |> Identity.list_by_ids() |> Map.new(&{&1.id, &1.email})

    Enum.reduce_while(rows, acc, fn row, {counts, error} ->
      email = Map.get(emails, row.user_id) || Map.get(accounts, row.user_id)

      result =
        if is_binary(email),
          do: adapter.unsubscribe(connection, email),
          else: :ok

      record(context, connection, row.user_id, email, "unsubscribed", result, now, row.email_hash)
      step(result, :unsubscribed, counts, error)
    end)
  end

  defp step(:ok, key, counts, error), do: {:cont, {Map.update!(counts, key, &(&1 + 1)), error}}

  defp step({:error, {:unauthorized, _} = reason}, _key, counts, _error),
    do: {:halt, {Map.update!(counts, :failed, &(&1 + 1)), reason}}

  defp step({:error, reason}, _key, counts, error),
    do: {:cont, {Map.update!(counts, :failed, &(&1 + 1)), error || reason}}

  defp record(context, connection, user_id, email, status, result, now, fallback_hash \\ nil) do
    hash = if is_binary(email), do: AudienceSyncPlan.email_hash(email), else: fallback_hash

    {status, error} =
      case result do
        :ok -> {status, nil}
        {:error, reason} -> {"failed", reason |> inspect() |> String.slice(0, 300)}
      end

    Integrations.record_audience_member(context, %{
      connection_id: connection.id,
      user_id: user_id,
      email_hash: hash || "",
      status: status,
      synced_at: now,
      last_error: error
    })
  end

  # Members of the box (client roles) with consent now and an email.
  defp wanted_contacts(context) do
    consented = MapSet.new(Integrations.consented_user_ids(context))
    clients = context |> Organizations.list_client_user_ids() |> MapSet.new()

    consented
    |> MapSet.intersection(clients)
    |> MapSet.to_list()
    |> Identity.list_by_ids()
    |> Enum.filter(&is_binary(&1.email))
    |> Enum.map(fn account ->
      %{
        user_id: account.id,
        email: account.email,
        first_name: AudienceSyncPlan.first_name(account.nickname)
      }
    end)
  end
end

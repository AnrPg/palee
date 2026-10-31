defmodule Palee.Status do
  @moduledoc """
  The public status page (ADR-364, CP-G4).

  * **Probes.** `record_probe/2` stores one round of dependency checks
    (`Palee.Status.Ports.DependencyProbe`): the latest state per component
    and the day's counts behind the uptime history (90 days).
  * **Incidents and maintenance** are written by the Palee team from the
    platform console (`create_incident/3`, `add_incident_update/4`,
    `edit_incident/3`); anyone reads them.
  * **Page data.** `overview/1` (now) and `history/2` (uptime per day) are
    public and need no session, so the page can be served by the web app or
    by a host outside the cluster.
  * **Subscribers** (`request_subscription/4`, `confirm_subscription/2`,
    `unsubscribe/1`): double opt-in, address and language only.
  """

  alias Palee.Infrastructure.Tenancy.RepoContext
  alias Palee.Status.Domain.{IncidentPolicy, Overview, SubscriberPolicy, Uptime}
  alias Palee.Status.StatusStore

  @history_since_days 90

  ## Probes

  def record_probe(results, %DateTime{} = now), do: StatusStore.record_probe(results, now)

  @doc "Deletes probe counts older than the history window and expired sign-ups."
  def sweep(%DateTime{} = now) do
    today = DateTime.to_date(now)

    %{
      samples: StatusStore.delete_samples_before(Date.add(today, -Uptime.max_days())),
      unconfirmed:
        StatusStore.delete_unconfirmed_before(SubscriberPolicy.unconfirmed_before(now))
    }
  end

  ## Public page

  @doc """
  The page now: overall status, components, active incidents and
  maintenance, upcoming maintenance.
  """
  def overview(%DateTime{} = now) do
    states = StatusStore.list_component_states()
    incidents = StatusStore.list_incidents(DateTime.add(now, -1, :day))
    summary = Overview.build(states, incidents, now)

    %{
      status: summary.status,
      components: summary.components,
      active: Enum.filter(incidents, &IncidentPolicy.active?(&1, now)),
      upcoming:
        incidents
        |> Enum.filter(&IncidentPolicy.upcoming?(&1, now))
        |> Enum.sort_by(& &1.scheduled_for, DateTime),
      generated_at: now
    }
  end

  @doc "Uptime per component and day over `days` days (1..90), and the incidents in that window."
  def history(days, %DateTime{} = now) do
    days = Uptime.window_days(days)
    last = DateTime.to_date(now)
    first = Uptime.first_day(last, days)
    since = DateTime.new!(first, ~T[00:00:00], "Etc/UTC")

    %{
      days: days,
      from: first,
      to: last,
      components: Uptime.history(StatusStore.list_samples(first, last), last, days),
      incidents:
        since
        |> StatusStore.list_incidents()
        |> Enum.filter(&(DateTime.compare(&1.started_at, now) != :gt)),
      generated_at: now
    }
  end

  ## Platform console (vendors)

  def console(context, %DateTime{} = now) do
    as_vendor(context, fn ->
      {:ok,
       %{
         states: StatusStore.list_component_states(),
         incidents: StatusStore.list_incidents(DateTime.add(now, -@history_since_days, :day)),
         subscribers: StatusStore.count_subscribers()
       }}
    end)
  end

  def create_incident(context, params, %DateTime{} = now) do
    as_vendor(context, fn ->
      with {:ok, attrs} <- IncidentPolicy.validate_new(params, now) do
        {update, attrs} = Map.pop(attrs, :update)

        StatusStore.create_incident(
          Map.put(attrs, :created_by_id, context.user_id),
          Map.put(update, :created_by_id, context.user_id)
        )
      end
    end)
  end

  def add_incident_update(context, id, params, %DateTime{} = now) do
    as_vendor(context, fn ->
      StatusStore.add_update(id, context.user_id, fn incident ->
        IncidentPolicy.validate_update(incident, params, now)
      end)
    end)
  end

  def edit_incident(context, id, params) do
    as_vendor(context, fn ->
      with {:ok, changes} <- IncidentPolicy.validate_edit(params) do
        StatusStore.edit_incident(id, changes)
      end
    end)
  end

  @doc "An update with its incident, for the notification job (system session)."
  def get_update_with_incident(update_id) do
    with %{} = update <- StatusStore.get_update(update_id),
         %{} = incident <- StatusStore.get_incident(update.incident_id) do
      {:ok, incident, update}
    else
      nil -> {:error, :not_found}
    end
  end

  ## Subscribers

  @doc """
  Records a sign-up and returns what to send: `{:ok, {:confirm, subscriber}}`
  (send the confirmation with the raw `token`), or `{:ok, :already_confirmed}`
  (send nothing).
  """
  def request_subscription(email, locale, token, %DateTime{} = _now) when is_binary(token) do
    with {:ok, email} <- SubscriberPolicy.normalize_email(email) do
      digest = SubscriberPolicy.digest(email)
      locale = SubscriberPolicy.locale(locale)
      token_digest = SubscriberPolicy.digest(token)

      case SubscriberPolicy.on_request(StatusStore.get_subscriber_by_digest(digest)) do
        :create ->
          email
          |> then(
            &StatusStore.create_subscriber(%{
              email: &1,
              email_digest: digest,
              locale: locale,
              confirm_token_digest: token_digest
            })
          )
          |> confirm_reply()

        :refresh ->
          digest
          |> StatusStore.get_subscriber_by_digest()
          |> StatusStore.refresh_subscriber(%{locale: locale, confirm_token_digest: token_digest})
          |> confirm_reply()

        :already_confirmed ->
          {:ok, :already_confirmed}
      end
    end
  end

  def confirm_subscription(token, %DateTime{} = now) when is_binary(token) do
    case StatusStore.confirm_subscriber(
           SubscriberPolicy.digest(token),
           SubscriberPolicy.unconfirmed_before(now),
           now
         ) do
      {:ok, subscriber} -> {:ok, subscriber}
      {:error, :not_found} -> {:error, :status_subscription_not_found}
    end
  end

  def confirm_subscription(_token, _now), do: {:error, :status_subscription_not_found}

  def get_subscriber(id), do: StatusStore.get_subscriber(id)

  def unsubscribe(subscriber_id) when is_binary(subscriber_id),
    do: StatusStore.delete_subscriber(subscriber_id)

  def list_confirmed_subscribers(after_id, limit),
    do: StatusStore.list_confirmed_subscribers(after_id, limit)

  defp confirm_reply({:ok, subscriber}), do: {:ok, {:confirm, subscriber}}
  defp confirm_reply({:error, _reason} = error), do: error

  defp as_vendor(%{vendor: vendor, user_id: user_id}, fun)
       when not is_nil(vendor) and is_binary(user_id),
       do: RepoContext.run(%{user_id: user_id}, fun)

  defp as_vendor(_context, _fun), do: {:error, :vendor_required}
end

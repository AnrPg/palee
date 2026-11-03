defmodule Palee.Status.Ports.StatusStore do
  @moduledoc """
  ADR-364: storage of the status page. Platform data (no tenant): component
  states, daily probe counts, incidents with their timeline, subscribers.
  Writes need a vendor session or a system session (no acting user).
  """

  alias Palee.Status.{ComponentState, DailySample, Incident, IncidentUpdate, Subscriber}

  @type id :: Ecto.UUID.t()
  @type result :: %{component: String.t(), status: String.t(), reason: String.t() | nil}

  @doc """
  Stores one probe round in a transaction: overwrites each component's
  state (`changed_at` moves only when the status changed) and adds the
  outcome to that UTC day's counts.
  """
  @callback record_probe([result()], DateTime.t()) :: :ok | {:error, term()}
  @callback list_component_states() :: [ComponentState.t()]
  @callback list_samples(Date.t(), Date.t()) :: [DailySample.t()]
  @callback delete_samples_before(Date.t()) :: non_neg_integer()

  @doc "Incidents still open, or closed at or after `since`, with their updates, newest first."
  @callback list_incidents(DateTime.t()) :: [Incident.t()]
  @callback get_incident(id()) :: Incident.t() | nil
  @callback create_incident(map(), map()) ::
              {:ok, Incident.t(), IncidentUpdate.t()} | {:error, term()}

  @doc """
  Locks the incident, asks `fun` for the changes (`{:ok, %{status, body,
  notify, resolved_at, started_at}}`), stores them with a new update.
  """
  @callback add_update(id(), id() | nil, (Incident.t() -> {:ok, map()} | {:error, term()})) ::
              {:ok, Incident.t(), IncidentUpdate.t()} | {:error, term()}
  @callback edit_incident(id(), map()) :: {:ok, Incident.t()} | {:error, term()}
  @callback get_update(id()) :: IncidentUpdate.t() | nil

  @callback get_subscriber_by_digest(String.t()) :: Subscriber.t() | nil
  @callback get_subscriber(id()) :: Subscriber.t() | nil
  @callback create_subscriber(map()) :: {:ok, Subscriber.t()} | {:error, term()}
  @callback refresh_subscriber(Subscriber.t(), map()) :: {:ok, Subscriber.t()} | {:error, term()}

  @doc """
  Confirms the waiting subscriber with this token digest whose request was
  made (or renewed) at or after `not_before`, and clears the token.
  """
  @callback confirm_subscriber(String.t(), DateTime.t(), DateTime.t()) ::
              {:ok, Subscriber.t()} | {:error, :not_found}
  @callback delete_subscriber(id()) :: :ok
  @callback delete_unconfirmed_before(DateTime.t()) :: non_neg_integer()

  @doc "Confirmed subscribers after `after_id` (id order), at most `limit`."
  @callback list_confirmed_subscribers(id() | nil, pos_integer()) :: [Subscriber.t()]
  @callback count_subscribers() :: %{confirmed: non_neg_integer(), waiting: non_neg_integer()}
end

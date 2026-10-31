defmodule Palee.Status.Domain.IncidentPolicy do
  @moduledoc """
  Rules for incidents and planned maintenance on the status page (ADR-364).

  * An **incident** moves `investigating → identified → monitoring →
    resolved`; steps may be skipped and it may go back (e.g. monitoring →
    investigating), but a resolved incident is closed.
  * A **maintenance** moves `scheduled → in_progress → completed`; it needs
    a window (`scheduled_for` before `scheduled_until`).
  * Impact: `none`, `minor` (some people notice), `major` (a component is
    down for many), `critical` (Palee does not work).
  * Every change carries a note people read (1–2000 characters). Titles are
    3–140 characters.

  Pure: callers pass `now`.
  """

  alias Palee.Status.Domain.Components

  @kinds ~w(incident maintenance)
  @impacts ~w(none minor major critical)
  @incident_statuses ~w(investigating identified monitoring resolved)
  @maintenance_statuses ~w(scheduled in_progress completed)
  @closed ~w(resolved completed)

  def kinds, do: @kinds
  def impacts, do: @impacts
  def statuses("incident"), do: @incident_statuses
  def statuses("maintenance"), do: @maintenance_statuses
  def all_statuses, do: @incident_statuses ++ @maintenance_statuses

  @doc "Whether the status closes the incident or maintenance."
  def closed?(status), do: status in @closed

  @doc """
  Validates a new incident or maintenance. Returns `{:ok, attrs}` with
  the incident fields (`kind`, `title`, `impact`, `status`, `components`,
  `scheduled_for`, `scheduled_until`, `started_at`, `resolved_at`) and the
  first update (`body`, `notify`), or `{:error, reason}`.
  """
  def validate_new(params, %DateTime{} = now) do
    kind = text(params, :kind) || "incident"
    impact = text(params, :impact) || default_impact(kind)

    with :ok <- check(kind in @kinds, :invalid_status_kind),
         {:ok, title} <- title(params),
         :ok <- check(impact in @impacts, :invalid_status_impact),
         {:ok, components} <- components(params),
         {:ok, window} <- window(kind, params),
         status = text(params, :status) || initial_status(kind),
         :ok <- check(status in statuses(kind), :invalid_status_transition),
         {:ok, body} <- body(params) do
      started_at = started_at(kind, status, window, now)

      {:ok,
       %{
         kind: kind,
         title: title,
         impact: impact,
         status: status,
         components: components,
         scheduled_for: window[:scheduled_for],
         scheduled_until: window[:scheduled_until],
         started_at: started_at,
         resolved_at: if(closed?(status), do: now),
         update: %{status: status, body: body, notify: notify?(params)}
       }}
    end
  end

  @doc """
  Validates a new step on an existing incident: `{:ok, %{status, body,
  notify, resolved_at, started_at}}`, where `resolved_at`/`started_at`
  are set only when this step closes or starts it.
  """
  def validate_update(%{kind: kind, status: current} = incident, params, %DateTime{} = now) do
    status = text(params, :status) || current

    with :ok <- check(not closed?(current), :status_incident_closed),
         :ok <- check(status in statuses(kind), :invalid_status_transition),
         {:ok, body} <- body(params) do
      {:ok,
       %{
         status: status,
         body: body,
         notify: notify?(params),
         resolved_at: if(closed?(status), do: now),
         started_at: maintenance_start(incident, status, now)
       }}
    end
  end

  @doc """
  Validates a correction to the title, impact or components (no note, no
  email): `{:ok, changes}` with only the given fields.
  """
  def validate_edit(params) do
    Enum.reduce_while([:title, :impact, :components], {:ok, %{}}, fn field, {:ok, acc} ->
      if has?(params, field) do
        case edit_field(field, params) do
          {:ok, value} -> {:cont, {:ok, Map.put(acc, field, value)}}
          {:error, _reason} = error -> {:halt, error}
        end
      else
        {:cont, {:ok, acc}}
      end
    end)
  end

  @doc """
  Whether the incident is on the page now: an open incident, or a
  maintenance that is in progress or whose window has started and not
  ended.
  """
  def active?(%{kind: "incident", status: status}, _now), do: not closed?(status)

  def active?(%{kind: "maintenance", status: "in_progress"}, _now), do: true

  def active?(%{kind: "maintenance", status: "scheduled"} = m, now),
    do:
      DateTime.compare(m.scheduled_for, now) != :gt and
        DateTime.compare(m.scheduled_until, now) == :gt

  def active?(_incident, _now), do: false

  @doc "Whether a maintenance is still to come."
  def upcoming?(%{kind: "maintenance", status: "scheduled"} = m, now),
    do: DateTime.compare(m.scheduled_for, now) == :gt

  def upcoming?(_incident, _now), do: false

  # -- fields --------------------------------------------------------------

  defp edit_field(:title, params), do: title(params)

  defp edit_field(:impact, params) do
    impact = text(params, :impact)
    if impact in @impacts, do: {:ok, impact}, else: {:error, :invalid_status_impact}
  end

  defp edit_field(:components, params), do: components(params)

  defp title(params) do
    title = params |> text(:title) |> trim()

    if is_binary(title) and String.length(title) in 3..140,
      do: {:ok, title},
      else: {:error, :invalid_status_title}
  end

  defp body(params) do
    body = params |> text(:body) |> trim()

    if is_binary(body) and String.length(body) in 1..2000,
      do: {:ok, body},
      else: {:error, :invalid_status_note}
  end

  defp components(params) do
    keys = get(params, :components) || []

    if is_list(keys) and Components.all_known?(keys),
      do: {:ok, Components.normalize(keys)},
      else: {:error, :unknown_status_component}
  end

  defp window("incident", _params), do: {:ok, %{}}

  defp window("maintenance", params) do
    with {:ok, from} <- datetime(get(params, :scheduled_for)),
         {:ok, until} <- datetime(get(params, :scheduled_until)),
         :gt <- DateTime.compare(until, from) do
      {:ok, %{scheduled_for: from, scheduled_until: until}}
    else
      _invalid -> {:error, :invalid_maintenance_window}
    end
  end

  defp started_at("maintenance", "scheduled", window, _now), do: window.scheduled_for
  defp started_at(_kind, _status, _window, now), do: now

  defp maintenance_start(%{kind: "maintenance", status: "scheduled"}, "in_progress", now),
    do: now

  defp maintenance_start(_incident, _status, _now), do: nil

  defp initial_status("incident"), do: "investigating"
  defp initial_status("maintenance"), do: "scheduled"

  defp default_impact("maintenance"), do: "minor"
  defp default_impact(_kind), do: "major"

  defp notify?(params) do
    case get(params, :notify) do
      false -> false
      "false" -> false
      _other -> true
    end
  end

  defp datetime(%DateTime{} = value), do: {:ok, value}

  defp datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      _error -> :error
    end
  end

  defp datetime(_value), do: :error

  defp check(true, _reason), do: :ok
  defp check(false, reason), do: {:error, reason}

  defp has?(params, key), do: Map.has_key?(params, key) or Map.has_key?(params, to_string(key))

  defp get(params, key), do: Map.get(params, key, Map.get(params, to_string(key)))

  defp text(params, key) do
    case get(params, key) do
      value when is_binary(value) ->
        value

      value when is_atom(value) and not is_nil(value) and not is_boolean(value) ->
        to_string(value)

      _other ->
        nil
    end
  end

  defp trim(nil), do: nil
  defp trim(value), do: String.trim(value)
end

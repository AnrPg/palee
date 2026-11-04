defmodule Palee.Notifications.Domain.NotificationFilter do
  @moduledoc """
  ADR-460: which of a person's notifications a list or a bulk delete covers
  («Εγώ › Ρυθμίσεις › Ειδοποιήσεις › Διαγραφή ειδοποιήσεων»), and how long a
  deleted one may still be restored («Αναίρεση» in the bell).

  A filter is `state` (`all` or `read`), `older_than_days` (whole days, from
  1) and `category` (an ADR-199 category id). Every part is optional; an
  empty filter covers every notification of the inbox. A bulk delete names
  either `ids` or a `filter`, never both, so "select all (N)" is sent as the
  filter itself and the server deletes exactly what it would list.

  Pure: the caller passes the current time.
  """

  alias Palee.Notifications.Domain.NotificationCategories

  @states ~w(all read)
  @max_older_than_days 3650
  @max_ids 200
  @restore_window_seconds 60

  @type t :: %{
          read_only: boolean(),
          inserted_before: NaiveDateTime.t() | nil,
          types: [String.t()] | nil
        }

  @doc "No filter: every notification of the inbox."
  @spec all() :: t()
  def all, do: %{read_only: false, inserted_before: nil, types: nil}

  @doc "The most ids one bulk delete may name."
  def max_ids, do: @max_ids

  @doc "Seconds after a delete during which «Αναίρεση» may still restore it."
  def restore_window_seconds, do: @restore_window_seconds

  @doc """
  Parses `state`, `older_than_days` and `category` (string or atom keys;
  numbers as integers or decimal strings). Unknown values are refused.
  """
  @spec parse(map(), DateTime.t()) :: {:ok, t()} | {:error, :bad_request}
  def parse(params, %DateTime{} = now) when is_map(params) do
    with {:ok, read_only} <- parse_state(param(params, :state)),
         {:ok, inserted_before} <- parse_age(param(params, :older_than_days), now),
         {:ok, types} <- parse_category(param(params, :category)) do
      {:ok, %{read_only: read_only, inserted_before: inserted_before, types: types}}
    end
  end

  def parse(_params, _now), do: {:error, :bad_request}

  @doc """
  Parses a bulk delete body: `%{ids: [...]}` or `%{filter: %{...}}`.
  """
  @spec parse_bulk(map(), DateTime.t()) ::
          {:ok, {:ids, [String.t()]} | {:filter, t()}} | {:error, :bad_request}
  def parse_bulk(body, now) when is_map(body) do
    case {param(body, :ids), param(body, :filter)} do
      {ids, nil} when is_list(ids) ->
        parse_ids(ids)

      {nil, filter} when is_map(filter) ->
        with {:ok, f} <- parse(filter, now), do: {:ok, {:filter, f}}

      _other ->
        {:error, :bad_request}
    end
  end

  def parse_bulk(_body, _now), do: {:error, :bad_request}

  @doc "Whether a notification deleted at `deleted_at` may still be restored at `now`."
  @spec restorable?(DateTime.t() | nil, DateTime.t()) :: boolean()
  def restorable?(nil, _now), do: false

  def restorable?(%DateTime{} = deleted_at, %DateTime{} = now),
    do: DateTime.diff(now, deleted_at, :second) <= @restore_window_seconds

  @doc "The earliest `deleted_at` a restore at `now` still accepts."
  @spec restorable_since(DateTime.t()) :: DateTime.t()
  def restorable_since(%DateTime{} = now),
    do: DateTime.add(now, -@restore_window_seconds, :second)

  defp parse_state(nil), do: {:ok, false}
  defp parse_state(state) when is_atom(state), do: parse_state(Atom.to_string(state))
  defp parse_state(state) when state in @states, do: {:ok, state == "read"}
  defp parse_state(_state), do: {:error, :bad_request}

  defp parse_age(nil, _now), do: {:ok, nil}

  defp parse_age(days, now)
       when is_integer(days) and days >= 1 and days <= @max_older_than_days do
    # `inserted_at` is a naive UTC column.
    {:ok, now |> DateTime.add(-days * 86_400, :second) |> DateTime.to_naive()}
  end

  defp parse_age(days, now) when is_binary(days) do
    case Integer.parse(days) do
      {parsed, ""} -> parse_age(parsed, now)
      _other -> {:error, :bad_request}
    end
  end

  defp parse_age(_days, _now), do: {:error, :bad_request}

  defp parse_category(nil), do: {:ok, nil}
  defp parse_category(""), do: {:ok, nil}

  defp parse_category(category) when is_binary(category) do
    case NotificationCategories.types_for(category) do
      nil -> {:error, :bad_request}
      types -> {:ok, types}
    end
  end

  defp parse_category(_category), do: {:error, :bad_request}

  defp parse_ids([]), do: {:error, :bad_request}

  defp parse_ids(ids) when length(ids) > @max_ids, do: {:error, :bad_request}

  defp parse_ids(ids) do
    if Enum.all?(ids, &uuid?/1),
      do: {:ok, {:ids, Enum.uniq(ids)}},
      else: {:error, :bad_request}
  end

  defp uuid?(id) when is_binary(id), do: match?({:ok, _uuid}, Ecto.UUID.cast(id))
  defp uuid?(_id), do: false

  defp param(params, key), do: Map.get(params, key, Map.get(params, Atom.to_string(key)))
end

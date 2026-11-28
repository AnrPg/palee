defmodule Palee.ActivityLog do
  @moduledoc """
  ADR-760: the box's «Αρχείο ενεργειών»: who on the staff did what, when,
  to whom and why, for every change staff make (3A).

  * Recording. `PaleeWeb.Plugs.RecordActivity` writes one row for every
    staff request that changed something (`PaleeWeb.RouteActivity` names
    its key). A use case that knows more (the value before and after, the
    name of what it touched) adds it with `note/1` during the request;
    `record/2` writes a row directly (the system, a job).
  * Reading. `list/2` filters by what the reader's role may see
    (`Domain.Visibility`, 4A) and pages by time; `list_for_member/2` is the
    member's own view: only rows shared with them, without staff names
    (5A); `export_csv/2` is the same list as CSV (10A).
  * Rows are insert-only (8A). `forget_person/1` keeps what was done to a
    deleted account and drops its reason and details (9A).
  """

  alias Palee.ActivityLog.Domain.{Actions, Visibility}
  alias Palee.Identity
  alias Palee.Infrastructure.Tenancy.RepoContext

  require Logger

  @notes_key {__MODULE__, :notes}
  @page 50
  @export_max 10_000

  defp store, do: Application.fetch_env!(:palee, :activity_log_store)

  # ── Recording ───────────────────────────────────────────────────────────

  @doc """
  Adds to the row the current request will record: `subject_label`,
  `person_user_id`, `details` (merged, e.g. `changes: [%{field, before,
  after}]`), `reason`, `reason_shared`, or `action` when the use case knows
  better than the route (e.g. a state change that was a cancellation).
  Outside a request it does nothing harmful: the notes are dropped.
  """
  def note(attrs) when is_map(attrs) do
    current = Process.get(@notes_key, %{})

    merged =
      Map.merge(current, attrs, fn
        :details, old, new when is_map(old) and is_map(new) -> Map.merge(old, new)
        _key, _old, new -> new
      end)

    Process.put(@notes_key, merged)
    :ok
  end

  @doc "Takes (and clears) the notes of the current request."
  def take_notes, do: Process.delete(@notes_key) || %{}

  @doc "Clears notes left by an earlier request of this process."
  def clear_notes, do: Process.delete(@notes_key) && :ok

  @doc """
  Writes one row in the box of `context` (`organization_id`; `user_id` and
  `roles` are the actor; a context without `user_id` records the system).
  """
  def record(%{organization_id: organization_id} = context, attrs)
      when is_binary(organization_id) and is_map(attrs) do
    row =
      attrs
      |> Map.put_new(:actor_user_id, Map.get(context, :user_id))
      |> Map.put_new(:actor_roles, roles(context))
      |> Map.put_new(:source, if(Map.get(context, :user_id), do: "request", else: "system"))

    case RepoContext.run(%{organization_id: organization_id}, fn -> store().insert(row) end) do
      {:ok, entry} ->
        :telemetry.execute([:palee, :activity_log, :recorded], %{count: 1}, %{
          action: entry.action,
          area: entry.area
        })

        {:ok, entry}

      {:error, reason} = error ->
        Logger.error(
          "activity_log_record_failed action=#{inspect(attrs[:action])} " <>
            "organization_id=#{organization_id} reason=#{inspect(reason)}"
        )

        :telemetry.execute([:palee, :activity_log, :failed], %{count: 1}, %{
          action: attrs[:action]
        })

        error
    end
  end

  defp roles(context) do
    context
    |> Map.get(:roles, [])
    |> List.wrap()
    |> Enum.map(&to_string/1)
  end

  # ── Reading ─────────────────────────────────────────────────────────────

  @doc """
  The rows a staff member may read, newest first. `params` (string keys,
  all optional): `areas` (list or comma list), `person_id`, `actor_id`,
  `from`/`to` (ISO dates, the box's days, `to` included), `q` (text in the
  reason, the subject or a person's name), `cursor`, `limit`.
  `{:ok, %{entries, next_cursor}}` or `{:error, :forbidden}`.
  """
  def list(context, params \\ %{}) do
    with {:ok, filters} <- filters(context, params) do
      RepoContext.run(context, fn ->
        filters = with_name_matches(filters)
        rows = store().list(filters)
        {:ok, page(rows, filters.limit, &present(&1, :staff))}
      end)
    end
  end

  @doc """
  The member's own rows: only those staff shared with them (5A), without
  who on the staff did it. `{:ok, %{entries, next_cursor}}`.
  """
  def list_for_member(%{user_id: user_id} = context, params \\ %{}) when is_binary(user_id) do
    limit = limit(params)

    RepoContext.run(context, fn ->
      rows =
        store().list(%{
          person_user_id: user_id,
          shared_only: true,
          before: cursor(params["cursor"]),
          limit: limit + 1
        })

      {:ok, page(rows, limit, &present(&1, :member))}
    end)
  end

  @doc "The same rows as `list/2`, as CSV text (owner, admins, accountant; 10A)."
  def export_csv(context, params \\ %{}) do
    if Visibility.can_export?(Map.get(context, :capabilities)) do
      with {:ok, filters} <- filters(context, Map.put(params, "limit", @export_max)) do
        RepoContext.run(context, fn ->
          rows =
            filters |> with_name_matches() |> store().list() |> Enum.map(&present(&1, :staff))

          {:ok, Palee.ActivityLog.Csv.encode(rows)}
        end)
      end
    else
      {:error, :forbidden}
    end
  end

  @doc "Whether a reader may open the log at all (any area)."
  def readable?(context), do: Visibility.any?(Map.get(context, :capabilities))

  @doc "The owner's daily summary (12B): sensitive rows in `[from, to)`."
  def sensitive_between(context, %DateTime{} = from, %DateTime{} = to) do
    RepoContext.run(context, fn ->
      %{sensitive_only: true, from: from, to: to, limit: 500}
      |> store().list()
      |> Enum.map(&present(&1, :staff))
    end)
  end

  defp filters(context, params) do
    readable = Visibility.readable(Map.get(context, :capabilities))
    wanted = areas(params["areas"])

    all = names(readable.all, wanted)
    own = names(readable.own, wanted) -- all

    if all == [] and own == [] do
      {:error, :forbidden}
    else
      {:ok,
       %{
         areas: all,
         own_areas: own,
         reader_id: context.user_id,
         person_user_id: uuid(params["person_id"]),
         actor_user_id: uuid(params["actor_id"]),
         actions: actions(params["actions"]),
         from: day_start(context, params["from"]),
         to: day_end(context, params["to"]),
         query: text(params["q"]),
         sensitive_only: params["sensitive"] in [true, "true", "1"],
         before: cursor(params["cursor"]),
         limit: limit(params) + 1
       }}
    end
  end

  defp names(areas, nil), do: Enum.map(areas, &Atom.to_string/1)

  defp names(areas, wanted),
    do: areas |> Enum.map(&Atom.to_string/1) |> Enum.filter(&(&1 in wanted))

  defp areas(nil), do: nil
  defp areas(""), do: nil
  defp areas(value) when is_binary(value), do: areas(String.split(value, ","))

  defp areas(values) when is_list(values) do
    known = Enum.map(Actions.areas(), &Atom.to_string/1)
    values |> Enum.map(&String.trim(to_string(&1))) |> Enum.filter(&(&1 in known))
  end

  defp areas(_value), do: nil

  defp actions(nil), do: nil
  defp actions(value) when is_binary(value), do: actions(String.split(value, ","))
  defp actions(values) when is_list(values), do: Enum.filter(values, &Actions.known?/1)
  defp actions(_value), do: nil

  defp uuid(value) when is_binary(value) do
    case Ecto.UUID.cast(value) do
      {:ok, id} -> id
      :error -> nil
    end
  end

  defp uuid(_value), do: nil

  defp text(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      text -> String.slice(text, 0, 100)
    end
  end

  defp text(_value), do: nil

  defp limit(params) do
    case Integer.parse(to_string(params["limit"] || @page)) do
      {n, _rest} when n > 0 -> min(n, @export_max)
      _other -> @page
    end
  end

  # The box's own days (ADR-176): `from` at its midnight, `to` the next one.
  defp day_start(context, value), do: local_midnight(context, value, 0)
  defp day_end(context, value), do: local_midnight(context, value, 1)

  defp local_midnight(context, value, add_days) when is_binary(value) do
    with {:ok, date} <- Date.from_iso8601(value),
         zone when is_binary(zone) <-
           Palee.Organizations.organization_timezone(context.organization_id),
         {:ok, at} <- DateTime.new(Date.add(date, add_days), ~T[00:00:00], zone) do
      DateTime.shift_zone!(at, "Etc/UTC")
    else
      {:ambiguous, first, _second} -> DateTime.shift_zone!(first, "Etc/UTC")
      {:gap, _before, after_gap} -> DateTime.shift_zone!(after_gap, "Etc/UTC")
      _invalid -> nil
    end
  end

  defp local_midnight(_context, _value, _add_days), do: nil

  # Free text also finds rows by the names of the people in them.
  defp with_name_matches(%{query: nil} = filters), do: filters

  defp with_name_matches(%{query: query} = filters) do
    needle = fold(query)

    ids =
      store().people_ids()
      |> Identity.list_by_ids()
      |> Enum.filter(fn account -> String.contains?(fold(account.nickname || ""), needle) end)
      |> Enum.map(& &1.id)

    Map.put(filters, :matching_user_ids, ids)
  end

  defp fold(text) do
    text
    |> String.normalize(:nfd)
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.downcase()
  end

  # ── Pages and shapes ────────────────────────────────────────────────────

  defp page(rows, limit, present) do
    {shown, rest} = Enum.split(rows, limit)
    names = names_of(shown)

    entries = Enum.map(shown, &present.(Map.put(&1, :names, names)))

    next =
      case {rest, List.last(shown)} do
        {[_ | _], %{occurred_at: at, id: id}} -> encode_cursor(at, id)
        _none -> nil
      end

    %{entries: entries, next_cursor: next}
  end

  defp names_of(rows) do
    rows
    |> Enum.flat_map(&[&1.actor_user_id, &1.person_user_id])
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Identity.list_by_ids()
    |> Map.new(&{&1.id, &1.nickname})
  end

  defp present(%{} = row, audience) do
    names = Map.get(row, :names, %{})

    base = %{
      id: row.id,
      occurred_at: row.occurred_at,
      action: row.action,
      area: row.area,
      person: person(row.person_user_id, names),
      subject: row.subject || %{},
      subject_label: row.subject_label,
      details: row.details || %{},
      reason: row.reason,
      redacted: not is_nil(row.redacted_at)
    }

    case audience do
      :member ->
        base

      :staff ->
        Map.merge(base, %{
          actor: actor(row, names),
          reason_shared: row.reason_shared,
          sensitive: row.sensitive,
          source: row.source
        })
    end
  end

  defp person(nil, _names), do: nil
  defp person(id, names), do: %{id: id, name: Map.get(names, id)}

  defp actor(%{actor_user_id: nil}, _names), do: nil

  defp actor(%{actor_user_id: id, actor_roles: roles}, names),
    do: %{id: id, name: Map.get(names, id), roles: roles || []}

  defp encode_cursor(%DateTime{} = at, id),
    do: Base.url_encode64(DateTime.to_iso8601(at) <> "|" <> id, padding: false)

  defp cursor(value) when is_binary(value) do
    with {:ok, raw} <- Base.url_decode64(value, padding: false),
         [at, id] <- String.split(raw, "|", parts: 2),
         {:ok, at, _offset} <- DateTime.from_iso8601(at),
         {:ok, id} <- Ecto.UUID.cast(id) do
      {at, id}
    else
      _invalid -> nil
    end
  end

  defp cursor(_value), do: nil

  # ── People and tenant data ──────────────────────────────────────────────

  @doc "9A: a deleted account keeps what was done, without reasons or details."
  def forget_person(user_id) when is_binary(user_id) do
    _count = store().forget_person(user_id)
    :ok
  end

  def tenant_data_policy, do: Palee.ActivityLog.Domain.TenantDataPolicy.policy()

  def tenant_data_inventory(context),
    do: Palee.TenantData.TableStore.inventory(tenant_data_policy(), context)

  def export_tenant_data(context, mode \\ :full),
    do: Palee.TenantData.TableStore.export(tenant_data_policy(), context, mode)

  def purge_tenant_data(context),
    do: Palee.TenantData.TableStore.purge(tenant_data_policy(), context)

  @doc false
  def store_module, do: store()
end

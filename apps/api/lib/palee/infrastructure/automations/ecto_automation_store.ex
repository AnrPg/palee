defmodule Palee.Infrastructure.Automations.EctoAutomationStore do
  @moduledoc "ADR-346: recipe choices, the automatic-message outbox and members' preferences in Postgres."

  @behaviour Palee.Automations.Ports.AutomationStore

  import Ecto.Query

  alias Palee.Automations.{BoxAutomation, Delivery, MemberPreference}
  alias Palee.Repo

  @impl true
  def list_automations(context),
    do: context |> scoped(BoxAutomation) |> order_by([a], asc: a.recipe) |> Repo.all()

  @impl true
  def get_automation(context, recipe),
    do: context |> scoped(BoxAutomation) |> where([a], a.recipe == ^recipe) |> Repo.one()

  @impl true
  def put_automation(context, recipe, attrs) do
    (get_automation(context, recipe) || %BoxAutomation{recipe: recipe})
    |> BoxAutomation.changeset(Map.put(attrs, :recipe, recipe))
    |> Repo.insert_or_update()
  end

  @impl true
  def enqueue(context, attrs) do
    case existing(context, attrs) do
      %Delivery{} = delivery ->
        {:ok, delivery, :existing}

      nil ->
        # Called outside any transaction: a concurrent insert of the same
        # trigger loses on the unique index and reads the winner.
        case attrs |> Delivery.create_changeset() |> Repo.insert() do
          {:ok, delivery} ->
            {:ok, delivery, :created}

          {:error, %Ecto.Changeset{errors: errors} = changeset} ->
            if Keyword.has_key?(errors, :organization_id),
              do: {:ok, existing(context, attrs), :existing},
              else: {:error, changeset}
        end
    end
  end

  defp existing(context, attrs) do
    context
    |> scoped(Delivery)
    |> where([d], d.recipe == ^attrs.recipe and d.trigger_ref == ^attrs.trigger_ref)
    |> Repo.one()
  end

  @impl true
  def claim_due(context, %DateTime{} = now, limit, timeout_seconds) do
    stale = DateTime.add(now, -timeout_seconds, :second)

    candidates =
      context
      |> scoped(Delivery)
      |> where(
        [d],
        (d.status == "pending" and d.due_at <= ^now) or
          (d.status == "sending" and d.claimed_at < ^stale)
      )
      |> order_by([d], asc: d.due_at)
      |> limit(^limit)
      |> lock("FOR UPDATE SKIP LOCKED")
      |> select([d], d.id)

    {_count, rows} =
      Delivery
      |> where([d], d.id in subquery(candidates))
      |> select([d], d)
      |> Repo.update_all(
        set: [status: "sending", claimed_at: now, updated_at: now],
        inc: [attempts: 1]
      )

    Enum.sort_by(rows, & &1.due_at, DateTime)
  end

  @impl true
  def finish(context, id, changes) do
    case context |> scoped(Delivery) |> where([d], d.id == ^id) |> Repo.one() do
      nil -> {:error, :not_found}
      delivery -> delivery |> Delivery.finish_changeset(changes) |> Repo.update()
    end
  end

  @impl true
  def list_deliveries(context, filters) do
    limit = filters |> Map.get(:limit, 50) |> min(200) |> max(1)

    context
    |> scoped(Delivery)
    |> filter(:recipe, Map.get(filters, :recipe))
    |> filter(:user_id, Map.get(filters, :user_id))
    |> filter(:lead_id, Map.get(filters, :lead_id))
    |> filter(:status, Map.get(filters, :status))
    |> order_by([d], desc: d.due_at, desc: d.id)
    |> limit(^limit)
    |> Repo.all()
  end

  defp filter(query, _field, nil), do: query
  defp filter(query, field, value), do: where(query, [d], field(d, ^field) == ^value)

  @impl true
  def delivery_stats(context, %DateTime{} = since) do
    context
    |> scoped(Delivery)
    |> where([d], d.inserted_at >= ^since)
    |> group_by([d], [d.recipe, d.status])
    |> select([d], {d.recipe, d.status, count(d.id)})
    |> Repo.all()
    |> Enum.reduce(%{}, fn {recipe, status, count}, acc ->
      Map.update(acc, recipe, %{status => count}, &Map.put(&1, status, count))
    end)
  end

  @impl true
  def cancel_pending(context, filters) do
    now = DateTime.utc_now()

    {count, _rows} =
      context
      |> scoped(Delivery)
      |> where([d], d.status == "pending")
      |> filter(:recipe, Map.get(filters, :recipe))
      |> filter(:user_id, Map.get(filters, :user_id))
      |> filter(:lead_id, Map.get(filters, :lead_id))
      |> Repo.update_all(
        set: [
          status: "cancelled",
          skip_reason: Map.get(filters, :reason, "cancelled"),
          updated_at: now
        ]
      )

    count
  end

  @impl true
  def get_preference(context, user_id),
    do: context |> scoped(MemberPreference) |> where([p], p.user_id == ^user_id) |> Repo.one()

  @impl true
  def put_preference(context, user_id, attrs) do
    (get_preference(context, user_id) || %MemberPreference{user_id: user_id})
    |> MemberPreference.changeset(Map.put(attrs, :user_id, user_id))
    |> Repo.insert_or_update()
  end

  @impl true
  def birthdays(context, month, day) do
    context
    |> scoped(MemberPreference)
    |> where([p], p.birthday_month == ^month and p.birthday_day == ^day)
    |> where([p], is_nil(p.opted_out_at))
    |> where([p], fragment("NOT ('birthday' = ANY(?))", p.opted_out_recipes))
    |> select([p], p.user_id)
    |> Repo.all()
  end

  defp scoped(%{organization_id: organization_id}, queryable) when is_binary(organization_id),
    do: from(row in queryable, where: row.organization_id == ^organization_id)

  defp scoped(_context, queryable), do: from(row in queryable, where: false)
end

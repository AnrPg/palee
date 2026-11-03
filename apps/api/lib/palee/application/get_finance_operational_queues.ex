defmodule Palee.Application.GetFinanceOperationalQueues do
  alias Palee.Application.{BranchReport, DebtorContacts}
  alias Palee.{Finance, Identity}

  def call(params \\ %{}) do
    queues = Finance.operational_queues(params)
    users = user_map(queues)

    {:ok, %{queues: enrich_queues(queues, users)}}
  end

  @doc "ADR-186 §7: the queues of the people of the filtered branches."
  def call(context, params) do
    params = Map.new(params || %{}, fn {key, value} -> {to_string(key), value} end)
    report = BranchReport.resolve(context, params)
    queues = Finance.operational_queues(context, BranchReport.scope_params(params, report))
    users = user_map(queues)
    kept = DebtorContacts.labels(context, Map.keys(users))

    {:ok,
     %{
       queues: queues |> enrich_queues(users) |> with_kept_contacts(kept),
       branch_filter: BranchReport.filter_payload(report)
     }}
  end

  # ADR-396: a profile deleted while it owes the box shows the name the box
  # kept for the debt, with how to reach the person, not «Deleted account».
  defp with_kept_contacts(queues, kept) when map_size(kept) == 0, do: queues

  defp with_kept_contacts(queues, kept) do
    Map.new(queues, fn
      {key, rows} when is_list(rows) ->
        {key, Enum.map(rows, &kept_contact(&1, kept))}

      other ->
        other
    end)
  end

  defp kept_contact(%{} = row, kept) do
    case Map.get(kept, Map.get(row, :user_id) || Map.get(row, :recipient_user_id)) do
      nil ->
        row

      contact ->
        row
        |> Map.put(:user_label, contact.display_name)
        |> Map.put(:kept_contact, contact)
    end
  end

  defp kept_contact(row, _kept), do: row

  defp enrich_queues(queues, users) do
    queues
    |> Map.update(
      :expiring_memberships,
      [],
      &Enum.map(&1, fn row -> put_user_label(row, users, row.user_id) end)
    )
    |> Map.update(
      :pending_payments,
      [],
      &Enum.map(&1, fn row -> put_user_label(row, users, Map.get(row, :user_id)) end)
    )
    |> Map.update(
      :open_charges,
      [],
      &Enum.map(&1, fn row -> put_user_label(row, users, row.user_id) end)
    )
    |> Map.update(
      :pending_referral_rewards,
      [],
      &Enum.map(&1, fn row -> put_user_label(row, users, row.recipient_user_id) end)
    )
    |> Map.update(
      :promotion_redemptions,
      [],
      &Enum.map(&1, fn row -> put_user_label(row, users, Map.get(row, :user_id)) end)
    )
  end

  defp put_user_label(row, users, user_id) do
    user = Map.get(users, user_id)

    row
    |> Map.put(:nickname, user && Map.get(user, :nickname))
    |> Map.put(:user_label, (user && Map.get(user, :nickname)) || short_id(user_id))
  end

  defp user_map(queues) do
    queues
    |> Map.take([
      :expiring_memberships,
      :pending_payments,
      :open_charges,
      :pending_referral_rewards,
      :promotion_redemptions
    ])
    |> Map.values()
    |> List.flatten()
    |> Enum.flat_map(fn row -> [Map.get(row, :user_id), Map.get(row, :recipient_user_id)] end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Identity.list_by_ids()
    |> Map.new(&{&1.id, %{nickname: &1.nickname, role: to_string(&1.role)}})
  end

  defp short_id(nil), do: "Unknown"
  defp short_id(id), do: String.slice(to_string(id), 0, 8)
end

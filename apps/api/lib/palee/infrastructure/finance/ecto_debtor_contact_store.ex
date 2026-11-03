defmodule Palee.Infrastructure.Finance.EctoDebtorContactStore do
  @moduledoc "ADR-450: Postgres storage of deleted debtors' kept contacts (tenant RLS)."

  @behaviour Palee.Finance.Ports.DebtorContactStore

  import Ecto.Query

  alias Palee.Finance.DebtorContact
  alias Palee.Repo

  @impl true
  def keep(attrs) do
    attrs
    |> DebtorContact.changeset()
    |> Repo.insert(on_conflict: :nothing, conflict_target: [:organization_id, :membership_id])
    |> case do
      {:ok, _contact} -> :ok
      {:error, changeset} -> {:error, changeset}
    end
  end

  @impl true
  def for_users([]), do: %{}

  def for_users(user_ids) when is_list(user_ids) do
    DebtorContact
    |> where([c], c.user_id in ^user_ids)
    |> order_by([c], asc: c.kept_at)
    |> Repo.all()
    |> Map.new(&{&1.user_id, normalize(&1)})
  end

  @impl true
  def list do
    DebtorContact
    |> order_by([c], asc: c.kept_at)
    |> Repo.all()
    |> Enum.map(&normalize/1)
  end

  @impl true
  def release([]), do: 0

  def release(membership_ids) when is_list(membership_ids) do
    {count, _rows} =
      DebtorContact
      |> where([c], c.membership_id in ^membership_ids)
      |> Repo.delete_all()

    count
  end

  defp normalize(%DebtorContact{} = contact),
    do:
      Map.take(contact, [
        :membership_id,
        :user_id,
        :display_name,
        :email,
        :phone_e164,
        :locale,
        :kept_at
      ])
end

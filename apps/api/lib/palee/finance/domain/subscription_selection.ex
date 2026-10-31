defmodule Palee.Finance.Domain.SubscriptionSelection do
  @moduledoc """
  Pure ordering and eligibility rules for stacked subscriptions (ADR-096).

  Recurring subscriptions are tried first (newest first) because their
  allowances reset; one-off packages follow by earliest expiry so the units
  that would lapse first are consumed first.
  """

  alias Palee.Finance.Domain.{PackageCatalog, PackageContract, PackageType}

  def order(subscriptions) do
    {one_off, recurring} = Enum.split_with(subscriptions, &one_off?/1)

    recurring =
      Enum.sort_by(recurring, &{date_key(field(&1, :starts_on)), timestamp(&1)}, :desc)

    one_off =
      Enum.sort_by(one_off, &{expiry_key(field(&1, :ends_on)), timestamp(&1)}, :asc)

    recurring ++ one_off
  end

  def one_off?(subscription) do
    case PackageType.fetch(type(subscription)) do
      {:ok, type} -> PackageType.one_off?(type)
      _ -> false
    end
  end

  def type(subscription),
    do: PackageContract.type_from_params(field(subscription, :params_snapshot))

  @doc "Inclusive end date for a new subscription of a package that has a validity."
  def ends_on(%Date{} = starts_on, params) do
    case PackageContract.fields_from_params(params)["terms.validity"] do
      nil -> nil
      validity -> PackageCatalog.duration_end(starts_on, validity)
    end
  end

  @doc """
  Checks who may take a package, for a membership's subscription history
  (ADR-096, ADR-342). `history` contains every prior subscription (any
  status) as maps with `:membership_package_id`, `:params_snapshot`,
  `:status`, `:starts_on` and `:ends_on`.

  `opts`:
    * `:channel` – `:staff` (staff assign it, the default) or `:member` (the
      member buys or asks for it themselves);
    * `:today` – the gym-local day, for «active members only».

  Rules, in order: staff-only packages (`terms.buyers`), once per person,
  how many times one person may buy it (`terms.max_purchases_per_person`),
  new members only (intro offers), the packages one must hold or have held
  first (`terms.prerequisite_package_ids`) and «active members only».
  """
  def eligible?(package_id, params, history, opts \\ []) do
    fields = PackageContract.fields_from_params(params)
    channel = Keyword.get(opts, :channel, :staff)
    today = Keyword.get(opts, :today)
    bought = Enum.count(history, &(field(&1, :membership_package_id) == package_id))

    cond do
      fields["terms.buyers"] == "staff_only" and channel == :member ->
        {:error, :package_staff_only}

      fields["terms.once_per_person"] and bought > 0 ->
        {:error, :package_already_used}

      is_integer(fields["terms.max_purchases_per_person"]) and
          bought >= fields["terms.max_purchases_per_person"] ->
        {:error, :package_purchase_limit_reached}

      fields["terms.new_members_only"] and Enum.any?(history, &(type(&1) != "trial")) ->
        {:error, :package_new_members_only}

      missing_prerequisite?(fields["terms.prerequisite_package_ids"], history) ->
        {:error, :package_prerequisite_missing}

      fields["terms.buyers"] == "active_members" and
          not Enum.any?(history, &active_on?(&1, today)) ->
        {:error, :package_active_members_only}

      true ->
        :ok
    end
  end

  defp missing_prerequisite?(ids, history) when is_list(ids) and ids != [] do
    not Enum.any?(history, &(field(&1, :membership_package_id) in ids))
  end

  defp missing_prerequisite?(_ids, _history), do: false

  # Without a day, any active subscription counts.
  defp active_on?(subscription, today) do
    field(subscription, :status) == "active" and
      (is_nil(today) or
         (not after?(field(subscription, :starts_on), today) and
            not before?(field(subscription, :ends_on), today)))
  end

  defp after?(%Date{} = date, today), do: Date.compare(date, today) == :gt
  defp after?(_date, _today), do: false

  defp before?(%Date{} = date, today), do: Date.compare(date, today) == :lt
  defp before?(_date, _today), do: false

  def renewable?(params) do
    fields = PackageContract.fields_from_params(params)

    with {:ok, type} <- PackageType.fetch(PackageContract.type_from_params(params)),
         true <- PackageType.renewable?(type),
         true <- fields["terms.auto_renew"] do
      :ok
    else
      _ -> {:error, :package_not_renewable}
    end
  end

  defp field(map, key), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))

  defp date_key(nil), do: 0
  defp date_key(%Date{} = date), do: Date.to_gregorian_days(date)

  defp expiry_key(nil), do: :infinity
  defp expiry_key(%Date{} = date), do: Date.to_gregorian_days(date)

  defp timestamp(subscription) do
    case field(subscription, :inserted_at) do
      %DateTime{} = at ->
        DateTime.to_unix(at, :microsecond)

      %NaiveDateTime{} = at ->
        at |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_unix(:microsecond)

      _ ->
        0
    end
  end
end

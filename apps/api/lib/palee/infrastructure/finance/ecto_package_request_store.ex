defmodule Palee.Infrastructure.Finance.EctoPackageRequestStore do
  @moduledoc "ADR-291: packages waiting to be paid at the front desk, in Postgres (RLS by tenant)."

  @behaviour Palee.Finance.Ports.PackageRequestStore

  import Ecto.Query

  alias Palee.Finance.{
    FinanceInvoice,
    Membership,
    MembershipPackageSubscription,
    MembershipPayment,
    PackageRequest,
    PackageWaitBooking
  }

  alias Palee.Infrastructure.Tenancy.RepoContext
  alias Palee.Repo

  @impl true
  def request(params) do
    Repo.transaction(fn ->
      today = Map.fetch!(params, :today)

      case open_for(params.user_id, params.membership_package_id) do
        %PackageRequest{} = existing ->
          if Date.compare(existing.hold_until, today) == :lt do
            # Its 14 days ended before the hourly run closed it.
            lapse!(existing)
            insert!(params)
          else
            {normalize(existing), :existing}
          end

        nil ->
          insert!(params)
      end
    end)
    |> case do
      {:ok, {request, how}} -> {:ok, request, how}
      {:error, reason} -> {:error, reason}
    end
  end

  defp lapse!(request) do
    now = DateTime.utc_now()

    request
    |> PackageRequest.close_changeset(%{status: "lapsed", closed_at: now})
    |> Repo.update!()
  end

  defp insert!(params) do
    params
    |> PackageRequest.create_changeset()
    |> Repo.insert()
    |> case do
      {:ok, request} -> {normalize(request), :created}
      {:error, changeset} -> Repo.rollback(conflict_or(changeset))
    end
  end

  # Two presses at once: the unique index refuses the second insert.
  defp conflict_or(%Ecto.Changeset{errors: errors} = changeset) do
    if Keyword.has_key?(errors, :organization_id), do: :package_request_exists, else: changeset
  end

  defp open_for(user_id, package_id) do
    PackageRequest
    |> tenant_scope()
    |> where([r], r.user_id == ^user_id and r.membership_package_id == ^package_id)
    |> where([r], r.status == "pending")
    |> Repo.one()
  end

  @impl true
  def get(id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} ->
        PackageRequest |> tenant_scope() |> where([r], r.id == ^id) |> Repo.one() |> normalize()

      :error ->
        nil
    end
  end

  @impl true
  def list_open(%Date{} = today, opts) do
    PackageRequest
    |> tenant_scope()
    |> where([r], r.status == "pending" and r.hold_until >= ^today)
    |> maybe_user(opts[:user_id])
    |> maybe_users(opts[:user_ids])
    |> order_by([r], asc: r.inserted_at, asc: r.id)
    |> Repo.all()
    |> Enum.map(&normalize/1)
  end

  defp maybe_user(query, nil), do: query
  defp maybe_user(query, user_id), do: where(query, [r], r.user_id == ^user_id)

  defp maybe_users(query, nil), do: query
  defp maybe_users(query, user_ids), do: where(query, [r], r.user_id in ^user_ids)

  @impl true
  def close(id, status, params) do
    Repo.transaction(fn ->
      with {:ok, id} <- Ecto.UUID.cast(id),
           %PackageRequest{} = request <- locked(id) do
        # A package given another way fulfilled it first (ADR-291
        # addendum); the desk's «Είσπραξη» still adds its payment.
        if request.status == "pending" or
             (request.status == "activated" and status == "activated" and
                is_nil(request.membership_payment_id)) do
          request
          |> PackageRequest.close_changeset(Map.put(params, :status, status))
          |> Repo.update()
          |> case do
            {:ok, closed} -> normalize(closed)
            {:error, changeset} -> Repo.rollback(changeset)
          end
        else
          Repo.rollback({:package_request_closed, request.status})
        end
      else
        _ -> Repo.rollback(:not_found)
      end
    end)
  end

  defp locked(id) do
    PackageRequest
    |> tenant_scope()
    |> where([r], r.id == ^id)
    |> lock("FOR UPDATE")
    |> Repo.one()
  end

  @impl true
  def lapse_before(%Date{} = today, %DateTime{} = now) do
    {_count, rows} =
      PackageRequest
      |> tenant_scope()
      |> where([r], r.status == "pending" and r.hold_until < ^today)
      |> select([r], r)
      |> Repo.update_all(set: [status: "lapsed", closed_at: now, updated_at: now])

    Enum.map(rows, &normalize/1)
  end

  # However the package reached the person (an assignment, «+ Πληρωμή»,
  # the desk queue, an import), a request it answered never keeps saying
  # «Περιμένει πληρωμή»: the hourly run closes what a write missed.
  @impl true
  def fulfil_answered(%DateTime{} = now) do
    paid_after_request =
      from(payment in MembershipPayment,
        left_join: invoice in FinanceInvoice,
        on: invoice.id == payment.finance_invoice_id,
        where:
          (payment.membership_package_subscription_id == parent_as(:subscription).id or
             invoice.membership_package_subscription_id == parent_as(:subscription).id) and
            payment.payment_status == "paid" and is_nil(payment.deleted_at) and
            payment.inserted_at >= parent_as(:request).inserted_at,
        select: 1
      )

    answered =
      from(request in PackageRequest,
        as: :request,
        join: membership in Membership,
        on:
          membership.user_id == request.user_id and
            membership.organization_id == request.organization_id,
        join: subscription in MembershipPackageSubscription,
        as: :subscription,
        on:
          subscription.membership_id == membership.id and
            subscription.membership_package_id == request.membership_package_id,
        where:
          request.status == "pending" and subscription.status in ["active", "paused"] and
            is_nil(subscription.removed_on),
        where: subscription.inserted_at >= request.inserted_at or exists(paid_after_request),
        order_by: [asc: subscription.inserted_at],
        select: {request.id, subscription.id}
      )
      |> tenant_scope()
      |> Repo.all()
      # The first subscription that answered each request.
      |> Enum.uniq_by(&elem(&1, 0))

    Enum.flat_map(answered, fn {request_id, subscription_id} ->
      case close(request_id, "activated", %{
             closed_at: now,
             membership_package_subscription_id: subscription_id
           }) do
        {:ok, closed} -> [closed]
        {:error, _closed_meanwhile} -> []
      end
    end)
  end

  @impl true
  def claim_wait_booking(user_id, scheduled_class_id, allowed, %Date{} = today, %DateTime{} = now)
      when is_integer(allowed) and allowed >= 0 do
    Repo.transaction(fn ->
      # One person's bookings are counted one at a time, so two at once
      # cannot both take the last place.
      lock_person!(user_id)

      request = oldest_open(user_id, today)
      counted = request && counted_for_class(user_id, scheduled_class_id)

      cond do
        is_nil(request) ->
          Repo.rollback(:no_pending_request)

        counted ->
          # The same class booked again after a cancel: already counted.
          {:counted, counted.id}

        wait_bookings_used(user_id) >= allowed ->
          Repo.rollback(:wait_bookings_used)

        true ->
          %PackageWaitBooking{
            user_id: user_id,
            package_request_id: request.id,
            scheduled_class_id: scheduled_class_id,
            booked_at: now
          }
          |> Ecto.Changeset.change()
          |> Ecto.Changeset.unique_constraint([:organization_id, :user_id, :scheduled_class_id],
            name: :finance_package_wait_bookings_one_per_class_index
          )
          |> Repo.insert()
          |> case do
            {:ok, row} -> {:claimed, row.id}
            {:error, _changeset} -> Repo.rollback(:wait_bookings_used)
          end
      end
    end)
  end

  defp lock_person!(user_id) do
    organization_id = RepoContext.current_setting("app.organization_id")

    Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 717))", [
      "package_wait_bookings:#{organization_id}:#{user_id}"
    ])
  end

  defp counted_for_class(user_id, scheduled_class_id) do
    PackageWaitBooking
    |> tenant_scope()
    |> where([w], w.user_id == ^user_id and w.scheduled_class_id == ^scheduled_class_id)
    |> Repo.one()
  end

  defp oldest_open(user_id, today) do
    PackageRequest
    |> tenant_scope()
    |> where([r], r.user_id == ^user_id and r.status == "pending" and r.hold_until >= ^today)
    |> order_by([r], asc: r.inserted_at, asc: r.id)
    |> limit(1)
    |> Repo.one()
  end

  @impl true
  def release_wait_booking(wait_booking_id) do
    PackageWaitBooking
    |> tenant_scope()
    |> where([w], w.id == ^wait_booking_id)
    |> Repo.delete_all()

    :ok
  end

  @impl true
  def wait_bookings_used(user_id) do
    PackageWaitBooking
    |> tenant_scope()
    |> where([w], w.user_id == ^user_id)
    |> select([w], count(w.id))
    |> Repo.one()
  end

  @impl true
  def wait_bookings_used_by([]), do: %{}

  def wait_bookings_used_by(user_ids) when is_list(user_ids) do
    PackageWaitBooking
    |> tenant_scope()
    |> where([w], w.user_id in ^user_ids)
    |> group_by([w], w.user_id)
    |> select([w], {w.user_id, count(w.id)})
    |> Repo.all()
    |> Map.new()
  end

  defp tenant_scope(queryable) do
    case RepoContext.current_setting("app.organization_id") do
      organization_id when is_binary(organization_id) and organization_id != "" ->
        from(row in queryable, where: field(row, :organization_id) == ^organization_id)

      _ ->
        from(row in queryable, where: false)
    end
  end

  defp normalize(nil), do: nil

  defp normalize(%PackageRequest{} = request) do
    request
    |> Map.from_struct()
    |> Map.drop([:__meta__])
  end
end

defmodule Palee.Infrastructure.Finance.EctoPackageTermsStore do
  @moduledoc """
  ADR-770: package changes that reach the members who already hold the
  package, in Postgres (RLS by tenant). The rules are in
  `Palee.Finance.Domain.PackageTermChanges`; this module locks, reads and
  writes.
  """

  @behaviour Palee.Finance.Ports.PackageTermsStore

  import Ecto.Query

  alias Palee.Finance.{
    FinanceInvoice,
    FinanceInvoiceLine,
    FinanceStore,
    Membership,
    MembershipPackage,
    MembershipPackageSubscription,
    PackageTermChange,
    SubscriptionTermUpdate
  }

  alias Palee.Finance.Domain.PackageTermChanges
  alias Palee.Infrastructure.Tenancy.{GymClock, RepoContext}
  alias Palee.Repo

  @holder_statuses ~w(active paused)

  @impl true
  def preview(package_id, params) do
    Repo.transaction(fn ->
      with {:ok, %{before: before, after: after_change, package: _package}} <-
             save_package(package_id, params) do
        today = GymClock.today()
        holders = holders(package_id, today)
        summary = PackageTermChanges.summary(before, after_change)
        plans = Enum.map(holders, &{&1, plan(&1, before, after_change, today)})

        Repo.rollback(
          {:preview,
           %{
             holders_count: length(holders),
             needs_choice: PackageTermChanges.needs_choice?(summary, length(holders)),
             changes: Enum.map(summary, &present_change/1),
             earliest_next_on:
               plans
               |> Enum.map(fn {_holder, plan} -> plan.next && plan.next.effective_on end)
               |> Enum.filter(&match?(%Date{}, &1))
               |> Enum.min(Date, fn -> nil end),
             holders: Enum.map(plans, &present_holder/1)
           }}
        )
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> case do
      {:error, {:preview, preview}} -> {:ok, preview}
      {:error, reason} -> {:error, reason}
      {:ok, _never} -> {:error, :preview_failed}
    end
  end

  @impl true
  def update(package_id, params, choice, actor_id) do
    Repo.transaction(fn ->
      case save_package(package_id, params) do
        {:ok, %{before: before, after: after_change, package: package}} ->
          today = GymClock.today()
          holders = holders(package_id, today)
          summary = PackageTermChanges.summary(before, after_change)
          needs_choice? = PackageTermChanges.needs_choice?(summary, length(holders))
          apply_to = choice[:apply_to]

          cond do
            needs_choice? and apply_to not in ["active", "new_only"] ->
              Repo.rollback(:package_terms_choice_required)

            summary == [] or holders == [] ->
              %{package: package, notices: [], term_change_id: nil}

            true ->
              excluded = MapSet.new(choice[:excluded_subscription_ids] || [])
              apply_to = if needs_choice?, do: apply_to, else: "new_only"

              change =
                insert_change!(package_id, before, after_change, summary, %{
                  apply_to: apply_to,
                  excluded: excluded,
                  holders_count: length(holders),
                  actor_id: actor_id
                })

              notices =
                if apply_to == "active",
                  do:
                    holders
                    |> Enum.reject(&MapSet.member?(excluded, &1.subscription.id))
                    |> Enum.flat_map(&give(&1, change, before, after_change, today)),
                  else: []

              %{package: package, notices: notices, term_change_id: change.id}
          end

        {:error, reason} ->
          Repo.rollback(reason)
      end
    end)
  end

  @impl true
  def apply_due(subscription_id, %Date{} = on) do
    SubscriptionTermUpdate
    |> tenant_scope()
    |> where([u], u.subscription_id == ^subscription_id and u.status == "pending")
    |> where([u], u.effective_on <= ^on)
    |> lock("FOR UPDATE")
    |> Repo.one()
    |> case do
      nil -> false
      update -> apply_pending!(update)
    end
  end

  @impl true
  def apply_due_all(%Date{} = today) do
    SubscriptionTermUpdate
    |> tenant_scope()
    |> where([u], u.status == "pending" and u.effective_on <= ^today)
    |> select([u], u.id)
    |> Repo.all()
    |> Enum.flat_map(fn id ->
      {:ok, membership_ids} =
        Repo.transaction(fn ->
          SubscriptionTermUpdate
          |> where([u], u.id == ^id and u.status == "pending")
          |> lock("FOR UPDATE")
          |> Repo.one()
          |> case do
            nil ->
              []

            update ->
              apply_pending!(update)
              FinanceStore.refresh_member_entitlement(update.membership_id)
              [update.membership_id]
          end
        end)

      membership_ids
    end)
    |> Enum.uniq()
  end

  @impl true
  def for_subscriptions([]), do: %{}

  def for_subscriptions(ids) when is_list(ids) do
    SubscriptionTermUpdate
    |> tenant_scope()
    |> where([u], u.subscription_id in ^ids and u.status in ["pending", "applied"])
    |> order_by([u], desc: u.inserted_at)
    |> Repo.all()
    |> Enum.group_by(& &1.subscription_id)
    |> Map.new(fn {id, updates} ->
      {pending, applied} = Enum.split_with(updates, &(&1.status == "pending"))
      {id, (pending ++ applied) |> Enum.take(10) |> Enum.map(&present_update/1)}
    end)
  end

  # ── Saving ──────────────────────────────────────────────────────────────

  defp save_package(package_id, params) do
    case MembershipPackage
         |> tenant_scope()
         |> where([p], p.id == ^package_id)
         |> lock("FOR UPDATE")
         |> Repo.one() do
      nil ->
        {:error, :not_found}

      %MembershipPackage{} = stored ->
        before =
          PackageTermChanges.package_terms(
            stored.base_price_cents,
            stored.billing_period,
            stored.params || %{}
          )

        with {:ok, package} <- FinanceStore.update_package(package_id, params) do
          after_change =
            PackageTermChanges.package_terms(
              package.base_price_cents,
              package.billing_period,
              package.params || %{}
            )

          {:ok, %{before: before, after: after_change, package: package}}
        end
    end
  end

  defp insert_change!(package_id, before, after_change, summary, attrs) do
    keys =
      summary
      |> Enum.map(& &1.key)
      |> Enum.reject(
        &(&1 in [PackageTermChanges.price_key(), PackageTermChanges.billing_period_key()])
      )

    Repo.insert!(%PackageTermChange{
      membership_package_id: package_id,
      changed_by: attrs.actor_id,
      apply_to: attrs.apply_to,
      price_before_cents: before.price_cents,
      price_after_cents: after_change.price_cents,
      fields_before:
        before.fields
        |> Map.take(keys)
        |> Map.put(PackageTermChanges.billing_period_key(), before.billing_period),
      fields_after:
        after_change.fields
        |> Map.take(keys)
        |> Map.put(PackageTermChanges.billing_period_key(), after_change.billing_period),
      excluded_subscription_ids: MapSet.to_list(attrs.excluded),
      holders_count: attrs.holders_count
    })
  end

  # One holder: the changes that apply now are written at once; those from
  # the next period merge into the subscription's pending update (ζ).
  defp give(holder, change, before, after_change, today) do
    subscription = holder.subscription
    plan = plan(holder, before, after_change, today)
    now_fields = plan.now.fields

    if now_fields != %{} or not is_nil(plan.now.ends_on) do
      terms = PackageTermChanges.apply_terms(subscription, now_fields, nil)

      subscription
      |> Ecto.Changeset.change(
        params_snapshot: terms.params_snapshot,
        ends_on: plan.now.ends_on || subscription.ends_on
      )
      |> Repo.update!()

      insert_update!(holder, change, %{
        timing: "now",
        status: "applied",
        effective_on: today,
        fields: now_fields,
        price_cents: nil,
        changes: Enum.filter(plan.changes, &(&1.timing == :now)),
        applied_at: DateTime.utc_now()
      })
    end

    subscription = Repo.get!(MembershipPackageSubscription, subscription.id)

    own =
      PackageTermChanges.package_terms(
        subscription.price_cents_snapshot,
        subscription.billing_period_snapshot,
        subscription.params_snapshot || %{}
      )

    pending = pending_update(subscription.id)

    pending_terms =
      pending &&
        %{
          fields: pending.fields || %{},
          price_cents: pending.price_cents,
          effective_on: pending.effective_on
        }

    merged =
      PackageTermChanges.merge_pending(
        pending_terms,
        plan.next,
        now_fields,
        own.fields,
        own.price_cents
      )

    if pending do
      pending |> Ecto.Changeset.change(status: "superseded") |> Repo.update!()
    end

    if merged do
      insert_update!(holder, change, %{
        timing: "next_period",
        status: "pending",
        effective_on: merged.effective_on,
        fields: merged.fields,
        price_cents: merged.price_cents,
        changes:
          merged
          |> PackageTermChanges.pending_changes(own.fields, own.price_cents)
          |> Enum.map(&Map.put(&1, :timing, :next_period)),
        applied_at: nil
      })
    end

    FinanceStore.refresh_member_entitlement(holder.membership.id)

    if now_fields != %{} or plan.next do
      [
        %{
          user_id: holder.membership.user_id,
          subscription_id: subscription.id,
          term_change_id: change.id,
          now_count: map_size(now_fields),
          next_on: plan.next && plan.next.effective_on
        }
      ]
    else
      []
    end
  end

  defp insert_update!(holder, change, attrs) do
    Repo.insert!(%SubscriptionTermUpdate{
      subscription_id: holder.subscription.id,
      membership_id: holder.membership.id,
      user_id: holder.membership.user_id,
      term_change_id: change.id,
      timing: attrs.timing,
      status: attrs.status,
      effective_on: attrs.effective_on,
      price_cents: attrs.price_cents,
      fields: attrs.fields,
      changes: Enum.map(attrs.changes, &stored_change/1),
      applied_at: attrs.applied_at
    })
  end

  defp apply_pending!(%SubscriptionTermUpdate{} = update) do
    subscription =
      MembershipPackageSubscription
      |> where([s], s.id == ^update.subscription_id)
      |> lock("FOR UPDATE")
      |> Repo.one!()

    if still_renews?(subscription, update) do
      terms = PackageTermChanges.apply_terms(subscription, update.fields, update.price_cents)

      subscription
      |> Ecto.Changeset.change(
        params_snapshot: terms.params_snapshot,
        price_cents_snapshot: terms.price_cents_snapshot
      )
      |> Repo.update!()

      update
      |> Ecto.Changeset.change(status: "applied", applied_at: DateTime.utc_now())
      |> Repo.update!()

      true
    else
      # γ: the member stopped renewing, is leaving or the subscription ends
      # before the day: the change never reaches them.
      update |> Ecto.Changeset.change(status: "superseded") |> Repo.update!()
      false
    end
  end

  defp still_renews?(subscription, update) do
    membership = Repo.get(Membership, subscription.membership_id)

    subscription.status in @holder_statuses and is_nil(subscription.removed_on) and
      subscription.auto_renew != false and
      not (match?(%Date{}, subscription.ends_on) and
             Date.compare(subscription.ends_on, update.effective_on) == :lt) and
      !(membership &&
          (match?(%DateTime{}, membership.left_at) or match?(%Date{}, membership.leaving_on)))
  end

  defp pending_update(subscription_id) do
    SubscriptionTermUpdate
    |> where([u], u.subscription_id == ^subscription_id and u.status == "pending")
    |> lock("FOR UPDATE")
    |> Repo.one()
  end

  # ── Holders ─────────────────────────────────────────────────────────────

  # Everyone who holds the package now or from a later day: a running or
  # paused subscription that was not removed and has not ended.
  defp holders(package_id, today) do
    MembershipPackageSubscription
    |> tenant_scope()
    |> join(:inner, [s], m in Membership, on: m.id == s.membership_id)
    |> where([s], s.membership_package_id == ^package_id and s.status in ^@holder_statuses)
    |> where([s], is_nil(s.removed_on))
    # ADR-795: a package waiting for its first session takes the package as
    # it is on that day, so a change never reaches it in between.
    |> where([s], not s.awaiting_first_session)
    |> where([s], is_nil(s.ends_on) or s.ends_on >= ^today)
    |> order_by([s], asc: s.inserted_at)
    |> lock("FOR UPDATE")
    |> select([s, m], %{subscription: s, membership: m})
    |> Repo.all()
    |> attach_charged_starts()
  end

  defp attach_charged_starts([]), do: []

  defp attach_charged_starts(holders) do
    ids = Enum.map(holders, & &1.subscription.id)

    by_lines =
      from(line in FinanceInvoiceLine,
        join: invoice in FinanceInvoice,
        on: invoice.id == line.finance_invoice_id,
        where: line.membership_package_subscription_id in ^ids,
        select: {line.membership_package_subscription_id, invoice}
      )

    by_header =
      from(invoice in FinanceInvoice,
        where: invoice.membership_package_subscription_id in ^ids,
        select: {invoice.membership_package_subscription_id, invoice}
      )

    starts =
      (Repo.all(by_header) ++ Repo.all(by_lines))
      |> Enum.filter(fn {_id, invoice} ->
        invoice.invoice_type in ["subscription", "renewal"] and invoice.status != "void" and
          is_nil(invoice.deleted_at) and match?(%Date{}, invoice.service_period_start)
      end)
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1).service_period_start)

    Enum.map(holders, &Map.put(&1, :charged_starts, Map.get(starts, &1.subscription.id, [])))
  end

  defp plan(holder, before, after_change, today),
    do: PackageTermChanges.plan(holder, before, after_change, today, holder.charged_starts)

  # ── Presenting ──────────────────────────────────────────────────────────

  defp present_holder({holder, plan}) do
    %{
      subscription_id: holder.subscription.id,
      membership_id: holder.membership.id,
      user_id: holder.membership.user_id,
      next_period_on: plan.next && plan.next.effective_on,
      now_count: map_size(plan.now.fields),
      next_count: Enum.count(plan.changes, &(&1.timing == :next_period)),
      notes: Enum.map(plan.notes, &Atom.to_string/1)
    }
  end

  defp present_change(change),
    do: %{
      key: change.key,
      from: change.from,
      to: change.to,
      timing: Atom.to_string(change.timing),
      direction: Atom.to_string(direction(change))
    }

  defp direction(%{key: key, from: from, to: to}),
    do: PackageTermChanges.direction(key, from, to)

  defp stored_change(change) do
    %{
      "key" => change.key,
      "from" => change.from,
      "to" => change.to,
      "timing" => Atom.to_string(change.timing)
    }
  end

  defp present_update(%SubscriptionTermUpdate{} = update) do
    %{
      id: update.id,
      timing: update.timing,
      status: update.status,
      effective_on: update.effective_on,
      applied_at: update.applied_at,
      changes: update.changes || [],
      inserted_at: update.inserted_at
    }
  end

  defp organization_id, do: RepoContext.current_setting("app.organization_id")

  defp tenant_scope(queryable) do
    case organization_id() do
      organization_id when is_binary(organization_id) and organization_id != "" ->
        from(row in queryable, where: field(row, :organization_id) == ^organization_id)

      _none ->
        from(row in queryable, where: false)
    end
  end
end

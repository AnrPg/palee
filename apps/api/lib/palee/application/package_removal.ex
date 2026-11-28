defmodule Palee.Application.PackageRemoval do
  @moduledoc """
  ADR-660: «Αφαίρεση πακέτου». Staff remove a member's package completely,
  from today:

    * the package gives nothing from today (the subscription is cancelled
      and marked removed); the box membership is not touched (ADR-595: the
      box and the money are separate);
    * an unpaid invoice of the package that nobody paid anything on is
      voided or stays owed as the staff member chooses each time (only staff
      who manage billing may void it; for the front desk it always stays);
      what was paid and what is left on a partly paid invoice stay;
    * for a minute the removal can be undone («Αναίρεση»); then it settles:
      the member's upcoming bookings are cancelled (when nothing else keeps
      their access) and they hear about it (bell and push), with the reason
      only when staff ticked «Να τον δει και το μέλος».

  Whoever takes payments may remove a package; writing a debt off needs
  `manage_billing`. Every step is logged with who did it.

  «Αλλαγή πακέτου» is the same removal with `replacement_package_id`: the
  new package starts today in the same transaction (never two packages
  side by side by mistake, never a moment without one), the member is told
  their package changed, and undo takes the new package back as well.
  """

  require Logger

  alias Palee.Application.RevokeAccess
  alias Palee.{Finance, Notifications, Organizations, Scheduling}
  alias Palee.Finance.Domain.{PackageAssignmentPolicy, PackageRemovalPolicy}
  alias Palee.Organizations.Domain.TenantAuthorization
  alias Palee.Workers.SettlePackageRemovalJob

  @doc """
  What removing the member's package would do: the unpaid invoices nobody
  paid anything on, what stays owed, what was paid, the upcoming bookings
  and whether this staff member may void the invoices.
  """
  def preview(context, user_id, subscription_id) do
    with {:ok, membership} <- membership(context, user_id),
         {:ok, money} <- Finance.package_removal_preview(context, membership.id, subscription_id) do
      {:ok,
       Map.merge(money, %{
         upcoming_bookings: Scheduling.count_active_future_bookings_for_user(context, user_id),
         may_write_off: may_write_off?(context),
         undo_seconds: PackageRemovalPolicy.undo_seconds()
       })}
    end
  end

  @doc """
  Removes the package. `params`: `invoice_choice` (`"void"` or `"keep"`,
  needed when there is an unpaid invoice and the staff member may void it),
  `reason` (optional), `reason_shared` (the member sees the reason) and
  `replacement_package_id` (a package change: this package starts today).
  """
  def remove(context, user_id, subscription_id, params) when is_map(params) do
    replacement_id = blank_to_nil(Map.get(params, "replacement_package_id"))

    attrs = %{
      invoice_choice: Map.get(params, "invoice_choice"),
      may_write_off?: may_write_off?(context),
      actor_id: context.user_id,
      actor_roles: roles(context),
      reason: Map.get(params, "reason"),
      reason_shared: Map.get(params, "reason_shared") == true,
      replacement_package_id: replacement_id
    }

    with {:ok, membership} <- membership(context, user_id),
         :ok <- replacement_assignable(context, replacement_id),
         {:ok, removal} <- Finance.remove_package(context, membership.id, subscription_id, attrs) do
      # ADR-642: a package completes a purchase admission.
      if removal.replacement_subscription_id,
        do: Organizations.purchase_package_started(context.organization_id, user_id)

      if removal.leaving_changed,
        do:
          Organizations.set_box_access_until(context.organization_id, user_id, removal.leaving_on)

      log(context, "removed", removal)
      SettlePackageRemovalJob.schedule(context.organization_id, removal.id)
      {:ok, removal}
    end
  end

  @doc "Undoes a removal while its minute is open."
  def undo(context, user_id, removal_id) do
    with {:ok, membership} <- membership(context, user_id),
         {:ok, removal} <-
           Finance.undo_package_removal(context, membership.id, removal_id, context.user_id) do
      if removal.leaving_changed and match?(%Date{}, removal.leaving_on),
        do:
          Organizations.set_box_access_until(context.organization_id, user_id, removal.leaving_on)

      log(context, "undone", removal)
      {:ok, removal}
    end
  end

  @doc """
  Once the undo closed: cancels the member's upcoming bookings (unless
  another package or a grace still keeps their access) and tells them.
  Returns `{:snooze, seconds}` while the undo is open; `:ok` otherwise.
  Safe to run again: a removal is settled once and told once.
  """
  def settle(context, removal_id, now \\ DateTime.utc_now()) do
    case Finance.settle_package_removal(context, removal_id, now) do
      {:ok, {:wait, removal}} ->
        {:snooze, max(DateTime.diff(removal.undo_until, now, :second), 0) + 1}

      {:ok, {:skip, %{settled_at: %DateTime{}, cancelled_bookings: nil} = removal}} ->
        finish(context, removal)

      {:ok, {:skip, _removal}} ->
        :ok

      {:ok, {:settle, removal}} ->
        finish(context, removal)

      {:error, :not_found} ->
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Daily (from `SubscriptionExpiryJob`): settles any removal whose job never
  ran, so no removal is left half done.
  """
  def settle_overdue(context, now \\ DateTime.utc_now()) do
    context
    |> Finance.unsettled_package_removal_ids(now)
    |> Enum.each(&settle(context, &1, now))
  end

  defp finish(context, removal) do
    cancelled =
      if keeps_access?(context, removal.user_id),
        do: 0,
        else: RevokeAccess.cancel_upcoming_bookings(context, removal.user_id)

    with {:ok, settled} <- Finance.record_package_removal_bookings(context, removal.id, cancelled) do
      notify_member(context, settled)
      log(context, "settled", settled)
      :ok
    end
  end

  defp keeps_access?(context, user_id) do
    case Finance.get_member_profile(context, user_id) do
      %{membership: %{entitlement_status: status}} -> status in ["active", "grace"]
      _none -> false
    end
  end

  defp notify_member(context, removal) do
    box =
      context.organization_id
      |> List.wrap()
      |> Palee.Application.PublicBox.boxes()
      |> List.first() || %{}

    Notifications.process_event("package_removed", %{
      organization_id: context.organization_id,
      user_id: removal.user_id,
      removal_id: removal.id,
      box_name: Map.get(box, :name),
      box_slug: Map.get(box, :slug),
      package_name: removal.package_name,
      replacement_package_name: removal.replacement_package_name,
      cancelled_bookings: removal.cancelled_bookings || 0,
      reason: if(removal.reason_shared, do: removal.reason, else: nil)
    })
  end

  defp replacement_assignable(_context, nil), do: :ok

  defp replacement_assignable(context, package_id) do
    with {:ok, _uuid} <- Ecto.UUID.cast(package_id),
         package when not is_nil(package) <- Finance.get_package(context, package_id) do
      PackageAssignmentPolicy.can_assign?(package)
    else
      _missing -> {:error, :not_found}
    end
  end

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(_value), do: nil

  defp membership(context, user_id) do
    case Finance.get_member_profile(context, user_id) do
      %{membership: %{id: id} = membership} when is_binary(id) -> {:ok, membership}
      _none -> {:error, :not_found}
    end
  end

  defp may_write_off?(context), do: TenantAuthorization.can?(context, :manage_billing)

  defp roles(context) do
    context
    |> Map.get(:roles, [])
    |> List.wrap()
    |> Enum.map(&to_string/1)
  end

  defp log(context, event, removal) do
    Logger.info(
      "package_removal_#{event} removal_id=#{removal.id} " <>
        "organization_id=#{context.organization_id} membership_id=#{removal.membership_id} " <>
        "subscription_id=#{removal.subscription_id} user_id=#{removal.user_id} " <>
        "actor_id=#{Map.get(context, :user_id)} actor_roles=#{Enum.join(roles(context), ",")} " <>
        "invoice_choice=#{removal.invoice_choice} voided=#{removal.voided_invoice_count} " <>
        "cancelled_bookings=#{removal.cancelled_bookings} reason_given=#{not is_nil(removal.reason)} " <>
        "replacement_subscription_id=#{removal.replacement_subscription_id}"
    )
  end
end

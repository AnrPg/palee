defmodule Palee.Application.PackageRule do
  @moduledoc """
  ADR-633: «Χωρίς πακέτο, χωρίς κράτηση». In a box that sells packages, a
  client books classes only with a package, or with a grace or free access
  that has an end date (ADR-612). Nobody can press «Το θέλω» and keep
  booking without paying.

    * **The rule** (`check_booking/4`): a client with no Finance profile is
      refused (`:finance_package_required`). Someone with a profile is
      judged by their package as before (no package, an ended one or an
      overdue debt already refuse). Staff, staff placing someone and the
      platform's admins are not touched.
    * **One class while waiting**: someone whose first «Το θέλω» waits for
      the desk may book one class, once per person and box, whatever
      happens to that booking. If the request is declined or lapses, their
      upcoming bookings are cancelled (`end_waiting/2`).
    * **Start and rollout** (`daily/2`, from `SubscriptionExpiryJob`): the
      rule starts the first day the box sells a package. The clients already
      training then without a profile get a 14-day free access from the
      system (insert-only ledger, `actor_roles = ["system"]`), hear about it,
      and the staff who take payments get the list. A box that sells no
      package any more stops the rule.
  """

  require Logger

  alias Palee.Application.MemberBenefits
  alias Palee.{Finance, Notifications, Organizations, Scheduling}
  alias Palee.Finance.PackageRequestStore
  alias Palee.Organizations.Domain.MembershipPolicy

  @rollout_days 14
  @rollout_reason "package_rule_rollout"

  def rollout_days, do: @rollout_days
  def rollout_reason, do: @rollout_reason

  # ── The rule ─────────────────────────────────────────────────────────────

  @doc """
  Whether `actor` may book `slot` as far as the rule goes:
  `{:ok, :open}` (the rule does not apply, or their profile decides),
  `{:ok, {:first_class, request_id}}` (the one class while waiting; give it
  back with `release/2` if the booking is not made), or
  `{:error, :finance_package_required}`.
  """
  def check_booking(context, actor, slot, enabled? \\ true)

  def check_booking(_context, _actor, _slot, false), do: {:ok, :open}
  def check_booking(nil, _actor, _slot, _enabled?), do: {:ok, :open}
  def check_booking(_context, %{role: :admin}, _slot, _enabled?), do: {:ok, :open}

  def check_booking(%{organization_id: organization_id} = context, %{id: user_id}, slot, true)
      when is_binary(organization_id) do
    cond do
      not on?(context) -> {:ok, :open}
      is_nil(Organizations.buyer_role(context, user_id)) -> {:ok, :open}
      has_profile?(context, user_id) -> {:ok, :open}
      true -> claim_first_class(context, user_id, slot)
    end
  end

  def check_booking(_context, _actor, _slot, _enabled?), do: {:ok, :open}

  @doc "Gives the one class back when its booking was not made."
  def release(context, {:first_class, request_id}) do
    scoped(context, fn -> PackageRequestStore.release_first_class(request_id) end)
  end

  def release(_context, _rule), do: :ok

  @doc "Whether the rule holds at the box now."
  def on?(context), do: not is_nil(since(context))

  @doc """
  What the person sees before booking (ADR-633), for the booking screens:
  `rule` (whether it holds for them), `package_required` (they would be
  refused now), `first_class_available` and `pending_request`.
  """
  def standing(%{organization_id: organization_id} = context, user_id)
      when is_binary(organization_id) do
    applies? =
      on?(context) and not is_nil(Organizations.buyer_role(context, user_id)) and
        not has_profile?(context, user_id)

    if applies? do
      today = Organizations.local_today(organization_id)

      {pending, used} =
        scoped(context, fn ->
          {PackageRequestStore.list_open(today, user_id: user_id) != [],
           not is_nil(PackageRequestStore.first_class(user_id))}
        end)

      %{
        rule: true,
        pending_request: pending,
        first_class_available: pending and not used,
        package_required: not (pending and not used)
      }
    else
      %{
        rule: false,
        pending_request: false,
        first_class_available: false,
        package_required: false
      }
    end
  end

  def standing(_context, _user_id),
    do: %{
      rule: false,
      pending_request: false,
      first_class_available: false,
      package_required: false
    }

  defp claim_first_class(context, user_id, slot) do
    today = Organizations.local_today(context.organization_id)

    case scoped(context, fn ->
           PackageRequestStore.claim_first_class(user_id, slot.id, today, DateTime.utc_now())
         end) do
      {:ok, request} ->
        Logger.info(
          "package_rule_first_class organization_id=#{context.organization_id} " <>
            "user_id=#{user_id} request_id=#{request.id} scheduled_class_id=#{slot.id}"
        )

        {:ok, {:first_class, request.id}}

      {:error, reason} ->
        Logger.info(
          "package_rule_refused organization_id=#{context.organization_id} " <>
            "user_id=#{user_id} reason=#{reason}"
        )

        {:error, :finance_package_required}
    end
  end

  @doc """
  A request closed without a package (declined, lapsed): if the person
  still has no profile and nothing else waiting, their upcoming bookings (the one class) go, the
  places and visits are released.
  """
  def end_waiting(context, user_id) do
    if on?(context) and not has_profile?(context, user_id) and not waiting?(context, user_id) do
      case Scheduling.cancel_active_future_bookings_for_user(context, user_id) do
        {:ok, released} -> length(released)
        _error -> 0
      end
    else
      0
    end
  end

  # ── Start and rollout ────────────────────────────────────────────────────

  @doc """
  Once a day: starts the rule the first day the box sells a package (and
  gives the clients already training a 14-day free access), stops it when
  the box sells none. Returns `:started`, `:stopped` or `:unchanged`.
  """
  def daily(%{organization_id: organization_id} = context, now \\ DateTime.utc_now()) do
    sells? = sells_packages?(context)
    since = since(context)

    cond do
      sells? and is_nil(since) -> start(%{organization_id: organization_id}, now)
      not sells? and not is_nil(since) -> stop(context)
      true -> :unchanged
    end
  end

  defp sells_packages?(context),
    do: context |> Finance.list_packages() |> Enum.any?(&(Map.get(&1, :active) == true))

  defp start(context, now) do
    {:ok, _settings} = Finance.put_package_rule_since(context, now)
    today = Organizations.local_today(context.organization_id, now)
    ends_on = Date.add(today, @rollout_days - 1)

    buyers =
      context
      |> Organizations.member_roles_by_user()
      |> Enum.filter(fn {_user_id, facts} -> MembershipPolicy.buyer?(facts.roles) end)
      |> Enum.map(fn {user_id, _facts} -> user_id end)

    # Without a profile, or kept in by a «Δωρεάν»/«Δοκιμή» status with no end.
    given =
      buyers
      |> Enum.filter(&(not has_profile?(context, &1) or endless?(context, &1)))
      |> Enum.filter(&give_rollout(context, &1, ends_on))

    Logger.info(
      "package_rule_started organization_id=#{context.organization_id} " <>
        "rollout_count=#{length(given)} ends_on=#{ends_on}"
    )

    :telemetry.execute(
      [:palee, :finance, :package_rule, :started],
      %{count: 1, rollout: length(given)},
      %{}
    )

    if given != [], do: notify_started(context, given, ends_on)
    :started
  end

  defp give_rollout(context, user_id, ends_on) do
    case MemberBenefits.grant_as_system(context, user_id, %{
           "kind" => "free_access",
           "ends_on" => Date.to_iso8601(ends_on),
           "reason" => @rollout_reason,
           "idempotency_key" => "package-rule:#{context.organization_id}:#{user_id}"
         }) do
      {:ok, %{replayed: false}} ->
        end_endless(context, user_id)
        notify_grace(context, user_id, ends_on)
        true

      {:ok, %{replayed: true}} ->
        false

      {:error, reason} ->
        Logger.warning(
          "package_rule_rollout_failed organization_id=#{context.organization_id} " <>
            "user_id=#{user_id} reason=#{inspect(reason)}"
        )

        false
    end
  end

  # A status set without a package that opens access for ever.
  defp endless?(context, user_id) do
    case Finance.get_member_profile(context, user_id) do
      %{membership: %{entitlement_source: source}} -> source in ["trial", "comped"]
      _none -> false
    end
  end

  # After the rollout's 14 days the package decides: the hand-set status
  # ends and a placeholder «Δοκιμή»/«Δωρεάν» becomes plain active.
  defp end_endless(context, user_id) do
    _reset =
      Finance.reset_value_override(context, user_id, "status", %{reason: @rollout_reason})

    case Finance.get_member_profile(context, user_id) do
      %{membership: %{status: status}} when status in ["trial", "comped"] ->
        Finance.upsert_membership(context, user_id, %{"status" => "active"})

      _other ->
        :ok
    end

    with %{membership: membership} <- Finance.get_member_profile(context, user_id),
         do: Finance.refresh_member_entitlement(context, membership.id)
  end

  defp stop(context) do
    {:ok, _settings} = Finance.put_package_rule_since(context, nil)
    Logger.info("package_rule_stopped organization_id=#{context.organization_id}")
    :stopped
  end

  @doc """
  The staff's list (ADR-633 «Μετάβαση»): since when the rule holds and the
  people who got the rollout's free access, with its last day and whether
  they have a package by now.
  """
  def rollout(context) do
    grants =
      scoped(context, fn ->
        Palee.Finance.MemberBenefitStore.list_system_grants(@rollout_reason)
      end)

    people =
      grants |> Enum.map(& &1.user_id) |> Palee.Identity.list_by_ids() |> Map.new(&{&1.id, &1})

    %{
      since: since(context),
      people:
        Enum.map(grants, fn grant ->
          account = Map.get(people, grant.user_id)

          %{
            user_id: grant.user_id,
            display_name: account && account.nickname,
            handle: account && account.handle,
            avatar_url: account && account.avatar_url,
            ends_on: grant.ends_on,
            has_package: has_package?(context, grant.user_id)
          }
        end)
    }
  end

  # ── Notifications ────────────────────────────────────────────────────────

  defp notify_grace(context, user_id, ends_on) do
    box = box(context)

    Notifications.dispatch_event(:package_rule_grace, %{
      organization_id: context.organization_id,
      user_id: user_id,
      ends_on: Date.to_iso8601(ends_on),
      box_name: box && box.name,
      box_slug: box && box.slug
    })
  end

  defp notify_started(context, user_ids, ends_on) do
    Notifications.dispatch_event(:package_rule_started, %{
      organization_id: context.organization_id,
      count: length(user_ids),
      ends_on: Date.to_iso8601(ends_on)
    })
  end

  # ── Small things ─────────────────────────────────────────────────────────

  defp since(context), do: Map.get(Finance.get_finance_settings(context), :package_rule_since)

  defp has_profile?(context, user_id),
    do: not is_nil(Finance.get_member_profile(context, user_id))

  defp waiting?(context, user_id) do
    today = Organizations.local_today(context.organization_id)
    scoped(context, fn -> PackageRequestStore.list_open(today, user_id: user_id) end) != []
  end

  defp has_package?(context, user_id) do
    case Finance.get_member_profile(context, user_id) do
      %{membership: %{entitlement_source: source}} ->
        source in ["membership_package", "open_invoice", "overdue_invoice"]

      _none ->
        false
    end
  end

  defp box(context),
    do:
      context.organization_id
      |> List.wrap()
      |> Palee.Application.PublicBox.boxes()
      |> List.first()

  defp scoped(context, fun), do: PackageRequestStore.with_tenant_context(context, fun)
end

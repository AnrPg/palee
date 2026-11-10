defmodule Palee.Finance.Domain.MemberStatus do
  @moduledoc """
  ADR-274: a member's status is worked out from what they hold and what they
  owe, never typed in. Pure rules; the store gathers the facts.

  Two values come out:

    * `status`, what staff see: the subscription's state with the money
      folded in, so someone who has not paid never shows a green «Ενεργό».
      When several apply, the first one wins:

          former › leaving › cancelled › paused › expired › overdue ›
          unpaid › expiring › trial | comped › active

      (`no_package` for a finance profile that never held a package).
      ADR-595: `leaving` («Αποχώρησε») is someone who left the box while a
      package they kept still runs, `former` («Πρώην μέλος») someone whose
      last day has passed. Both come first: what they owe shows next to
      them, not instead of them;
    * `lifecycle`, the membership's stored `status` that access rules,
      reports and queues have always read (`active`, `trial`, `comped`,
      `expiring`, `paused`, `expired`, `cancelled`). Money never changes it:
      access already follows invoices through the entitlement (ADR-017).

  `unpaid` means a charge fell due and is not paid but the box's grace days
  still keep access; `overdue` means the grace is over (the entitlement is
  `blocked` for an overdue invoice).

  Staff may set the status by hand (`overridable/0`); see
  `Palee.Finance.Domain.ValueOverride` for how that is kept and when it ends.
  """

  alias Palee.Finance.Domain.MemberBenefits

  @expiring_window_days 30
  @statuses ~w(active trial comped unpaid overdue leaving expiring paused expired cancelled former no_package)
  @lifecycles ~w(active trial comped expiring paused expired cancelled)
  @overridable ~w(active trial comped paused expired cancelled)
  # ADR-633: «Δωρεάν» and «Δοκιμή» by hand had no end, so someone could
  # train for ever without a package. Free access now always has a last day
  # («Δώρο ή χάρη», ADR-612); the statuses still come from a free or trial
  # package, and overrides set before stay readable until the rollout ends them.
  @settable ~w(active paused expired cancelled)

  @doc "Every status staff can see."
  def statuses, do: @statuses

  @doc "The values a membership's stored status can take."
  def lifecycles, do: @lifecycles

  @doc "The statuses staff may set by hand (leaving with its rules has its own flow, ADR-220)."
  def overridable, do: @overridable
  @doc "ADR-633: the statuses staff may set by hand now (`overridable/0` minus the endless ones)."
  def settable, do: @settable

  @doc """
  Works the status out. `facts`:

    * `:today`;
    * `:left_at`, `:leaving_on`: the membership's leaving (ADR-220);
    * `:subscriptions`: every subscription of the membership (maps with
      `:status`, `:starts_on`, `:ends_on`, `:price_cents_snapshot`,
      `:package_type`, `:renews?` and `:period_last_day`);
    * `:frozen?`: a freeze covers today;
    * `:grace_days`: the box's slack after a subscription ends;
    * `:entitlement`: `%{status, source}` from `InvoiceLifecycle.entitlement/1`;
    * `:unpaid_due_on`: the oldest unpaid charge's due date, when it is today
      or earlier;
    * `:membership_expires_on`: the profile's own end date (only used for a
      profile without packages).
  """
  def derive(facts) do
    today = Map.fetch!(facts, :today)
    # A subscription that has not begun says nothing yet about today.
    subscriptions = facts |> Map.get(:subscriptions, []) |> Enum.filter(&started?(&1, today))
    current = current_subscription(subscriptions, today)
    base = base_status(current)

    status =
      cond do
        left?(facts, today) -> "former"
        leaving?(facts, today) -> "leaving"
        # ADR-612: access without a package that the box gave.
        current == nil and staff_free_access?(facts) -> "comped"
        subscriptions == [] -> no_package_status(facts, today)
        current == nil -> "expired"
        current.status == "paused" or Map.get(facts, :frozen?, false) -> "paused"
        blocked_for_money?(facts) -> "overdue"
        match?(%Date{}, Map.get(facts, :unpaid_due_on)) -> "unpaid"
        expiring?(current, today) -> "expiring"
        true -> base
      end

    %{status: status, lifecycle: lifecycle(status, base, current, subscriptions, facts, today)}
  end

  @doc """
  ADR-595: the one standing the member and the staff both see: the status
  (`status_shown`) and what the line under it says: the last day of a grace
  the member is in, the last day of a package kept after leaving, what is
  owed and since when. `membership` is a normalized finance profile.
  """
  def standing(membership, outstanding_cents, unpaid_since) when is_map(membership) do
    status = Map.get(membership, :status_shown) || Map.get(membership, :status)
    benefit = MemberBenefits.kind_of_source(Map.get(membership, :entitlement_source))

    %{
      status: status,
      grace_until: Map.get(membership, :entitlement_grace_until),
      # ADR-612: the grace or free access the box gave (its last day is
      # `grace_until`), so member and staff read the same line.
      benefit: benefit,
      access_until:
        if(status in ["leaving", "former"], do: Map.get(membership, :leaving_on), else: nil),
      outstanding_cents: max(outstanding_cents || 0, 0),
      unpaid_since: unpaid_since
    }
  end

  @doc "The stored membership status an overridden status gives."
  def lifecycle_of_override(value) when value in @overridable, do: value

  defp lifecycle(status, _base, _current, _subscriptions, _facts, _today)
       when status in ["cancelled", "former"],
       do: "cancelled"

  # A freeze shows as paused but keeps the membership's own state: the
  # freeze itself already moves the subscription's end (ADR-097).
  defp lifecycle("paused", base, current, _subscriptions, _facts, _today),
    do: if(current.status == "paused", do: "paused", else: base)

  # Inside the box's grace days after the last subscription ended the
  # member keeps access (the entitlement's subscription grace).
  defp lifecycle("expired", _base, _current, subscriptions, facts, today) do
    grace_days = max(Map.get(facts, :grace_days) || 0, 0)

    case last_ended_on(subscriptions) do
      %Date{} = ended when grace_days > 0 ->
        if Date.diff(today, ended) <= grace_days, do: "expiring", else: "expired"

      _other ->
        "expired"
    end
  end

  defp lifecycle("expiring", _base, _current, _subscriptions, _facts, _today), do: "expiring"

  defp lifecycle("no_package", _base, _current, _subscriptions, facts, today) do
    case Map.get(facts, :membership_expires_on) do
      %Date{} = ends -> if Date.compare(ends, today) == :lt, do: "expired", else: "active"
      _none -> "active"
    end
  end

  defp lifecycle(_status, base, _current, _subscriptions, _facts, _today), do: base

  defp last_ended_on(subscriptions) do
    subscriptions
    |> Enum.map(& &1.ends_on)
    |> Enum.filter(&match?(%Date{}, &1))
    |> Enum.max(Date, fn -> nil end)
  end

  # A profile without packages keeps the dates it was given by hand.
  defp no_package_status(facts, today) do
    case Map.get(facts, :membership_expires_on) do
      %Date{} = ends ->
        cond do
          Date.compare(ends, today) == :lt -> "expired"
          Date.diff(ends, today) <= @expiring_window_days -> "expiring"
          true -> "no_package"
        end

      _none ->
        "no_package"
    end
  end

  # The subscription that says what the member holds today: a running one
  # (a paused one counts), preferring the one that started last.
  defp current_subscription(subscriptions, today) do
    subscriptions
    |> Enum.filter(&(&1.status in ["active", "paused"] and running?(&1, today)))
    |> Enum.sort_by(&(&1.starts_on || today), {:desc, Date})
    |> List.first()
  end

  defp started?(subscription, today) do
    case subscription.starts_on do
      %Date{} = starts_on -> Date.compare(starts_on, today) != :gt
      _none -> true
    end
  end

  defp running?(subscription, today) do
    case subscription.ends_on do
      %Date{} = ends -> Date.compare(ends, today) != :lt
      _open -> true
    end
  end

  defp base_status(nil), do: "active"

  defp base_status(subscription) do
    cond do
      subscription.package_type == "trial" -> "trial"
      (subscription.price_cents_snapshot || 0) <= 0 -> "comped"
      true -> "active"
    end
  end

  # ADR-595: the last day is still theirs (the package lasts through it).
  defp left?(facts, today) do
    match?(%DateTime{}, Map.get(facts, :left_at)) and
      case Map.get(facts, :leaving_on) do
        %Date{} = leaving_on -> Date.compare(leaving_on, today) == :lt
        _none -> true
      end
  end

  defp leaving?(facts, today) do
    match?(%DateTime{}, Map.get(facts, :left_at)) and
      match?(%Date{}, Map.get(facts, :leaving_on)) and
      Date.compare(Map.get(facts, :leaving_on), today) != :lt
  end

  defp staff_free_access?(facts),
    do: match?(%{status: "active", source: "staff_free_access"}, Map.get(facts, :entitlement))

  defp blocked_for_money?(facts) do
    match?(%{status: "blocked", source: "overdue_invoice"}, Map.get(facts, :entitlement))
  end

  defp expiring?(subscription, today) do
    case last_day(subscription) do
      %Date{} = ends -> Date.diff(ends, today) <= @expiring_window_days
      nil -> false
    end
  end

  # A subscription that renews never "expires soon"; one with an end, or
  # whose renewal is off, ends on its last day.
  defp last_day(subscription) do
    cond do
      match?(%Date{}, subscription.ends_on) -> subscription.ends_on
      Map.get(subscription, :renews?, true) -> nil
      true -> Map.get(subscription, :period_last_day)
    end
  end
end

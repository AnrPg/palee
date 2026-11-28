defmodule Palee.Finance.Domain.PackageTermChanges do
  @moduledoc """
  ADR-770: when a change of a subscription package reaches the members who
  already hold it. Pure rules; the store does the writing.

  A purchase keeps a copy of the package's terms (price, billing period,
  contract fields). When staff save a change and choose «Και στα ενεργά
  μέλη», every changed term gets a timing per holder:

    * `now`: the term gives the member more (more visits, more class types,
      a longer booking window, a later cancellation cutoff, a longer
      validity…). It applies at once.
    * `next_period`: the term costs the member (a higher price, fewer
      visits…) or the price drops. A recurring subscription takes it from
      the start of its next period, so nothing already charged or paid
      changes. A member who stopped renewing, is leaving or whose
      subscription ends before then never gets it.
    * `never`: the term shapes the subscription itself (billing period,
      joining fee, commitment, beneficiaries…), or it would take from a
      one-charge package (a visit pack, a trial) already paid for, or it
      would shorten a validity or stop renewal the member holds.
    * `purchase_only`: the term only says who may buy (buyers, purchases
      per person, needed first…): holders are not affected.

  Name, description and tax category are read live from the package and are
  not terms here.
  """

  alias Palee.Finance.Domain.{PackageCatalog, PackageContract, SubscriptionCharges}

  @price "price"
  @billing_period "billing_period"

  @structural ~w(
    terms.stacking terms.conversion_package_id terms.minimum_commitment_months
    terms.joining_fee_cents terms.compatible_package_ids
    terms.beneficiaries terms.quota_sharing terms.allow_minor_beneficiaries
    terms.seats terms.seat_billing terms.enrollment terms.enrollment_domain
    personal_training.coach_id personal_training.format personal_training.group_size
  )

  @purchase_only ~w(
    terms.buyers terms.max_purchases_per_person terms.prerequisite_package_ids
    terms.new_members_only terms.once_per_person
  )

  # Lower is better for the member.
  @lower_is_better ~w(booking.cancellation_cutoff_hours online_coaching.response_sla_hours)

  # Taking these away from a holder is never done: the validity they bought
  # and the renewal they hold stay theirs.
  @never_when_worse ~w(terms.validity terms.auto_renew)

  @waitlist_rank %{"normal" => 0, "high" => 1}

  @type terms :: %{price_cents: integer(), billing_period: String.t(), fields: map()}
  @type change :: %{key: String.t(), from: term(), to: term()}

  def price_key, do: @price
  def billing_period_key, do: @billing_period

  @doc "The package terms of a stored package or subscription snapshot."
  def package_terms(price_cents, billing_period, params) do
    %{
      price_cents: price_cents || 0,
      billing_period: billing_period,
      fields: params |> PackageContract.fields_from_params() |> PackageCatalog.drop_removed()
    }
  end

  @doc """
  The terms that differ between two package states, price first, then the
  billing period, then the contract fields in catalog order.
  """
  @spec changes(terms(), terms()) :: [change()]
  def changes(before, after_change) do
    price =
      if before.price_cents != after_change.price_cents,
        do: [%{key: @price, from: before.price_cents, to: after_change.price_cents}],
        else: []

    period =
      if before.billing_period != after_change.billing_period,
        do: [
          %{key: @billing_period, from: before.billing_period, to: after_change.billing_period}
        ],
        else: []

    fields =
      PackageCatalog.keys()
      |> Enum.map(&%{key: &1, from: before.fields[&1], to: after_change.fields[&1]})
      |> Enum.reject(&(&1.from == &1.to))

    price ++ period ++ fields
  end

  @doc "Whether a billing period renews period by period."
  def recurring?(billing_period), do: SubscriptionCharges.period_months(billing_period) != nil

  @doc """
  `:better`, `:worse` or `:neutral` for the member, when a term moves from
  `from` to `to`. A change whose direction cannot be told is `:worse`, so
  it never reaches a holder before their next period.
  """
  def direction(@price, from, to) when is_integer(from) and is_integer(to),
    do: if(to < from, do: :better, else: :worse)

  def direction(key, from, to) do
    case PackageCatalog.fetch(key) do
      {:ok, spec} -> kind_direction(spec, key, from, to)
      _unknown -> :worse
    end
  end

  @doc "When a changed term reaches a holder (see the moduledoc)."
  def timing(key, from, to, recurring?) do
    cond do
      key == @billing_period -> :never
      key in @purchase_only -> :purchase_only
      key in @structural -> :never
      key == @price -> if recurring?, do: :next_period, else: :never
      true -> field_timing(key, direction(key, from, to), recurring?)
    end
  end

  defp field_timing(_key, direction, _recurring?) when direction in [:better, :neutral], do: :now
  defp field_timing(key, :worse, _recurring?) when key in @never_when_worse, do: :never
  defp field_timing(_key, :worse, true), do: :next_period
  defp field_timing(_key, :worse, false), do: :never

  @doc """
  The package change as staff see it in «Ισχύει και για τα ενεργά μέλη;»:
  each changed term with its timing for a holder on the package's terms.
  """
  def summary(before, after_change) do
    recurring? = recurring?(after_change.billing_period)

    Enum.map(changes(before, after_change), fn change ->
      Map.put(change, :timing, timing(change.key, change.from, change.to, recurring?))
    end)
  end

  @doc """
  Whether saving needs staff to choose «Και στα ενεργά μέλη» or «Μόνο στις
  νέες αγορές»: the package has holders and a change would reach them.
  """
  def needs_choice?(summary, holders_count),
    do: holders_count > 0 and Enum.any?(summary, &(&1.timing in [:now, :next_period]))

  @doc """
  What the change gives one holder. `holder` carries the subscription's
  stored terms (`price_cents_snapshot`, `billing_period_snapshot`,
  `params_snapshot`, `starts_on`, `ends_on`, `auto_renew`, `status`) and the
  membership's `left_at` and `leaving_on`; `before` and `after_change` are
  the package's terms; `charged_starts` the period starts already charged.

  Returns `%{now: %{fields:, ends_on:}, next: nil | %{fields:, price_cents:,
  effective_on:}, changes: [%{key, from, to, timing}], notes: [atom]}`.
  Notes: `:custom_price` (the subscription has its own price: kept),
  `:renewal_stopped` (no next period), `:ends_before` (it ends before its
  next period).
  """
  def plan(holder, before, after_change, %Date{} = today, charged_starts \\ []) do
    subscription = holder.subscription

    own =
      package_terms(
        subscription.price_cents_snapshot,
        subscription.billing_period_snapshot,
        subscription.params_snapshot || %{}
      )

    recurring? = recurring?(own.billing_period)
    changed_keys = before |> changes(after_change) |> Enum.map(& &1.key)

    {price_changes, price_notes} = price_change(changed_keys, own, before, after_change)

    field_changes =
      changed_keys
      |> Enum.reject(&(&1 in [@price, @billing_period]))
      |> Enum.map(&%{key: &1, from: own.fields[&1], to: after_change.fields[&1]})
      |> Enum.reject(&(&1.from == &1.to))

    timed =
      Enum.map(price_changes ++ field_changes, fn change ->
        Map.put(change, :timing, timing(change.key, change.from, change.to, recurring?))
      end)

    {next_on, next_notes} = next_period_start(holder, today, charged_starts)
    deferred? = Enum.any?(timed, &(&1.timing == :next_period))

    timed =
      if deferred? and is_nil(next_on),
        do: Enum.map(timed, &if(&1.timing == :next_period, do: %{&1 | timing: :never}, else: &1)),
        else: timed

    now_changes = Enum.filter(timed, &(&1.timing == :now))
    next_changes = Enum.filter(timed, &(&1.timing == :next_period))

    %{
      now: %{
        fields: Map.new(now_changes, &{&1.key, &1.to}),
        ends_on: extended_end(subscription, now_changes)
      },
      next:
        if(next_changes != [],
          do: %{
            fields:
              next_changes
              |> Enum.reject(&(&1.key == @price))
              |> Map.new(&{&1.key, &1.to}),
            price_cents: Enum.find_value(next_changes, &(&1.key == @price && &1.to)),
            effective_on: next_on
          }
        ),
      changes: timed,
      notes: Enum.uniq(price_notes ++ if(deferred?, do: next_notes, else: []))
    }
  end

  defp price_change(changed_keys, own, before, after_change) do
    cond do
      @price not in changed_keys -> {[], []}
      own.price_cents != before.price_cents -> {[], [:custom_price]}
      true -> {[%{key: @price, from: own.price_cents, to: after_change.price_cents}], []}
    end
  end

  @doc """
  The first day of the holder's next period, when a later change may begin:
  nil (with the reason) when the subscription does not renew, ends before
  it, or the member stopped renewing or is leaving. A period already
  charged ahead keeps its terms: the one after it is taken.
  """
  def next_period_start(holder, %Date{} = today, charged_starts \\ []) do
    subscription = holder.subscription
    membership = Map.get(holder, :membership) || %{}
    starts_on = subscription.starts_on

    cond do
      not recurring?(subscription.billing_period_snapshot) ->
        {nil, []}

      subscription.auto_renew == false or match?(%DateTime{}, Map.get(membership, :left_at)) or
          match?(%Date{}, Map.get(membership, :leaving_on)) ->
        {nil, [:renewal_stopped]}

      not match?(%Date{}, starts_on) ->
        {nil, []}

      true ->
        from = if Date.compare(today, starts_on) == :lt, do: starts_on, else: today
        charged = MapSet.new(charged_starts)
        start = first_uncharged_start(subscription, from, charged, 24)

        cond do
          is_nil(start) ->
            {nil, []}

          match?(%Date{}, subscription.ends_on) and
              Date.compare(start, subscription.ends_on) == :gt ->
            {nil, [:ends_before]}

          true ->
            {start, []}
        end
    end
  end

  defp first_uncharged_start(_subscription, _date, _charged, 0), do: nil

  defp first_uncharged_start(subscription, date, charged, left) do
    case SubscriptionCharges.period_at(subscription, date) do
      {_start, %Date{} = next_start} ->
        if MapSet.member?(charged, next_start),
          do: first_uncharged_start(subscription, next_start, charged, left - 1),
          else: next_start

      _none ->
        nil
    end
  end

  # A longer validity moves a one-charge package's end by the difference.
  defp extended_end(subscription, now_changes) do
    with %{from: %{} = from, to: %{} = to} <-
           Enum.find(now_changes, &(&1.key == "terms.validity")),
         false <- recurring?(subscription.billing_period_snapshot),
         %Date{} = starts_on <- subscription.starts_on,
         %Date{} = ends_on <- subscription.ends_on do
      delta =
        Date.diff(
          PackageCatalog.duration_end(starts_on, to),
          PackageCatalog.duration_end(starts_on, from)
        )

      if delta > 0, do: Date.add(ends_on, delta), else: nil
    else
      _other -> nil
    end
  end

  @doc """
  A later change into a still pending update (ADR-770 ζ): the newer value
  of a key wins, a key the new change applies now leaves the pending
  update, and a key back at the subscription's own value is dropped.
  `own_fields` and `own_price` are the subscription's stored terms.
  """
  def merge_pending(nil, next, _now_fields, _own_fields, _own_price), do: next

  def merge_pending(pending, next, now_fields, own_fields, own_price) do
    fields =
      pending.fields
      |> Map.merge((next && next.fields) || %{})
      |> Map.drop(Map.keys(now_fields))
      |> Enum.reject(fn {key, value} -> own_fields[key] == value end)
      |> Map.new()

    price =
      case next && next.price_cents do
        nil -> pending.price_cents
        price -> price
      end

    price = if price == own_price, do: nil, else: price

    if fields == %{} and is_nil(price),
      do: nil,
      else: %{
        fields: fields,
        price_cents: price,
        effective_on: (next && next.effective_on) || pending.effective_on
      }
  end

  @doc "The member-facing changes of a pending update: from the subscription's terms to its own."
  def pending_changes(next, own_fields, own_price) do
    price =
      if is_integer(next.price_cents),
        do: [%{key: @price, from: own_price, to: next.price_cents}],
        else: []

    fields =
      PackageCatalog.keys()
      |> Enum.filter(&Map.has_key?(next.fields, &1))
      |> Enum.map(&%{key: &1, from: own_fields[&1], to: next.fields[&1]})

    price ++ fields
  end

  @doc """
  The subscription's stored terms with `fields` and `price` applied:
  `%{params_snapshot:, price_cents_snapshot:}`.
  """
  def apply_terms(subscription, fields, price_cents) do
    params = subscription.params_snapshot || %{}

    merged =
      params
      |> PackageContract.fields_from_params()
      |> PackageCatalog.drop_removed()
      |> Map.merge(fields || %{})

    %{
      params_snapshot:
        PackageContract.to_params(%{
          package_type: PackageContract.type_from_params(params),
          fields: merged
        }),
      price_cents_snapshot: price_cents || subscription.price_cents_snapshot
    }
  end

  # ── Directions by value kind ────────────────────────────────────────────

  defp kind_direction(%{kind: :boolean}, _key, from, to) do
    if from == false and to == true, do: :better, else: :worse
  end

  defp kind_direction(%{kind: :quota}, _key, from, to), do: quota_direction(from, to)

  defp kind_direction(%{kind: :quota_by_id}, _key, from, to) do
    from = limits_by_id(from)
    to = limits_by_id(to)

    (Map.keys(from) ++ Map.keys(to))
    |> Enum.uniq()
    |> Enum.map(&quota_direction(Map.get(from, &1, :unlimited), Map.get(to, &1, :unlimited)))
    |> combine()
  end

  defp kind_direction(%{kind: :scope_ids}, _key, from, to) do
    cond do
      to == "all" -> :better
      from == "all" -> :worse
      is_list(from) and is_list(to) -> set_direction(from, to)
      true -> :worse
    end
  end

  defp kind_direction(%{kind: :enum_list}, _key, from, to)
       when is_list(from) and is_list(to),
       do: set_direction(from, to)

  defp kind_direction(%{kind: :duration}, _key, %{} = from, %{} = to) do
    start = ~D[2000-01-01]

    case Date.compare(
           PackageCatalog.duration_end(start, to),
           PackageCatalog.duration_end(start, from)
         ) do
      :gt -> :better
      _other -> :worse
    end
  end

  # nil: no limit.
  defp kind_direction(%{kind: :integer_or_null}, _key, from, to) do
    cond do
      is_nil(to) -> :better
      is_nil(from) -> :worse
      true -> number_direction(to - from)
    end
  end

  defp kind_direction(%{kind: kind}, key, from, to)
       when kind in [:integer, :gym_default_integer, :integer_option, :integer_option_or_null] and
              is_integer(from) and is_integer(to) do
    if key in @lower_is_better,
      do: number_direction(from - to),
      else: number_direction(to - from)
  end

  defp kind_direction(%{kind: :enum}, "booking.waitlist_priority", from, to) do
    case {Map.get(@waitlist_rank, from), Map.get(@waitlist_rank, to)} do
      {f, t} when is_integer(f) and is_integer(t) -> number_direction(t - f)
      _other -> :worse
    end
  end

  # A free-text note says nothing the member loses.
  defp kind_direction(%{kind: :string_or_null}, _key, _from, _to), do: :neutral

  # Times when classes may be booked: none means any time.
  defp kind_direction(%{kind: :time_windows}, _key, _from, to),
    do: if(to == [], do: :better, else: :worse)

  defp kind_direction(_spec, _key, _from, _to), do: :worse

  defp quota_direction(from, to) do
    case {quota_limit(from), quota_limit(to), quota_period(from) == quota_period(to)} do
      {_f, :unlimited, _same} -> :better
      {:unlimited, _t, _same} -> :worse
      {f, t, true} when is_integer(f) and is_integer(t) -> number_direction(t - f)
      _other -> :worse
    end
  end

  defp quota_limit(:unlimited), do: :unlimited
  defp quota_limit(%{"limit" => "unlimited"}), do: :unlimited
  defp quota_limit(%{"limit" => limit}) when is_integer(limit), do: limit
  defp quota_limit(_other), do: nil

  defp quota_period(%{"period" => period}), do: period
  defp quota_period(_other), do: nil

  defp limits_by_id(entries) when is_list(entries),
    do: Map.new(entries, &{&1["id"], &1})

  defp limits_by_id(_other), do: %{}

  defp set_direction(from, to) do
    from = MapSet.new(from)
    to = MapSet.new(to)

    if MapSet.subset?(from, to), do: :better, else: :worse
  end

  defp number_direction(difference) when difference > 0, do: :better
  defp number_direction(0), do: :neutral
  defp number_direction(_difference), do: :worse

  defp combine(directions) do
    cond do
      Enum.any?(directions, &(&1 == :worse)) -> :worse
      Enum.any?(directions, &(&1 == :better)) -> :better
      true -> :neutral
    end
  end
end

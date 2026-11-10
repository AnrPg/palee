defmodule Palee.Application.Finance.PackageRequests do
  @moduledoc """
  ADR-291: «Το θέλω». When a box takes no online payments, a person asks for
  a package in the app and pays for it at the front desk. The package waits
  as «Περιμένει πληρωμή» for 14 days, granting nothing and owing nothing,
  and shows in the desk's «Εκκρεμότητες». The desk's «Είσπραξη» records the
  money and assigns the package in one step (ADR-222/248: the receipt or
  invoice settles its first period, so no separate charge is issued).

  Prices are the ones the person was shown when asking.

  ADR-633: the staff who take payments hear of each new request (bell and
  push). «Ενεργοποίηση» is either «Εισπράχθηκαν X €» (`collect/4`) or
  «Εκκρεμεί πληρωμή» (`activate_unpaid/3`: the package starts now and its
  charge is owed, so the box's reminders, grace days and lock follow it).
  «Απόρριψη» (`decline/4`) always says why, and the person hears it. While
  a request waits, the person may book one class (`PackageRule`).
  """

  alias Palee.Application.{AssignFinanceMemberPackage, PackageRule, ReceiveFinancePayment}
  alias Palee.Application.Payments.PackageAudience
  alias Palee.Finance
  alias Palee.Finance.Domain.PackageRequestPolicy
  alias Palee.Finance.PackageRequestStore
  alias Palee.{Identity, Notifications, Organizations, Payments}
  alias Palee.Payments.Domain.PackageSale

  # ── The person ──────────────────────────────────────────────────────────

  @doc """
  Asks for a package the box lists to its people. Asking again for the same
  package while one is open returns that one (`created: false`).
  """
  def request(context, package_id) do
    today = today(context)

    with {:ok, package} <- requestable_package(context, package_id),
         # ADR-342: who may buy it, how often, intro-only and prerequisites.
         :ok <-
           Finance.purchase_eligibility(context, context.user_id, package.id, :member, today),
         {:ok, request, how} <-
           scoped(context, fn ->
             PackageRequestStore.request(%{
               user_id: context.user_id,
               membership_package_id: package.id,
               package_name_snapshot: package.name,
               price_cents_snapshot: package.base_price_cents,
               currency: package.currency || "EUR",
               source: "member",
               requested_by_id: context.user_id,
               hold_until: PackageRequestPolicy.hold_until(today),
               today: today
             })
           end) do
      if how == :created, do: notify_staff(context, request)
      {:ok, %{request: present(request, today), created: how == :created}}
    end
  end

  defp notify_staff(context, request) do
    person = Identity.find_by_id(request.user_id)

    Notifications.dispatch_event(:package_requested, %{
      organization_id: context.organization_id,
      package_request_id: request.id,
      person_nickname: person && person.nickname,
      member_user_id: request.user_id,
      package_name: request.package_name_snapshot,
      price_cents: request.price_cents_snapshot,
      currency: request.currency
    })
  end

  defp requestable_package(context, package_id) do
    with {:ok, id} <- cast_id(package_id),
         %{} = package <- Finance.get_package(context, id) || {:error, :not_found},
         true <- PackageRequestPolicy.requestable?(package) || {:error, :package_not_for_sale},
         true <-
           PackageSale.listed?(package, Payments.package_offer(context)) ||
             {:error, :package_not_for_sale},
         # ADR-553: what the person does not see they cannot ask for.
         :ok <- PackageAudience.check(context, package.id, context.user_id) do
      {:ok, package}
    end
  end

  @doc "The person's packages waiting for payment at this box."
  def mine(context) do
    today = today(context)

    scoped(context, fn ->
      today
      |> PackageRequestStore.list_open(user_id: context.user_id)
      |> Enum.map(&present(&1, today))
    end)
  end

  @doc "The person takes back a request that still waits."
  def cancel(context, request_id) do
    today = today(context)

    scoped(context, fn ->
      with %{} = request <- PackageRequestStore.get(request_id) || {:error, :not_found},
           true <- request.user_id == context.user_id || {:error, :not_found},
           true <-
             PackageRequestPolicy.open?(request, today) || {:error, :package_request_closed},
           {:ok, closed} <-
             PackageRequestStore.close(request.id, "cancelled", %{
               closed_at: DateTime.utc_now(),
               closed_by_id: context.user_id
             }) do
        {:ok, present(closed, today)}
      end
    end)
    |> closed_error()
    |> tap(fn
      {:ok, closed} -> PackageRule.end_waiting(context, closed.user_id)
      _error -> :ok
    end)
  end

  # ── The front desk ──────────────────────────────────────────────────────

  @doc """
  The «Περιμένουν πληρωμή» queue: open requests with the person each one is
  for (display name, @handle, avatar), so the desk can open their account.
  `user_ids` narrows the queue to a branch's people (ADR-186).
  """
  def for_desk(context, opts \\ []) do
    today = today(context)

    requests =
      scoped(context, fn ->
        PackageRequestStore.list_open(today, Keyword.take(opts, [:user_ids]))
      end)

    people =
      requests
      |> Enum.map(& &1.user_id)
      |> Identity.list_by_ids()
      |> Map.new(&{&1.id, &1})

    Enum.map(requests, fn request ->
      request |> present(today) |> Map.put(:person, person(Map.get(people, request.user_id)))
    end)
  end

  defp person(nil), do: nil

  defp person(account),
    do: %{
      user_id: account.id,
      display_name: account.nickname,
      handle: account.handle,
      avatar_url: account.avatar_url
    }

  @doc """
  «Είσπραξη»: staff took the money at the desk. Records it (the box's
  document per ADR-222, its fiscal document per ADR-262) and assigns the
  package in the same Finance transaction, then closes the request. Safe to
  retry: the money is recorded once per request.
  """
  def collect(context, request_id, admin_id, params) do
    today = today(context)
    params = Map.new(params || %{}, fn {key, value} -> {to_string(key), value} end)

    with %{} = request <-
           scoped(context, fn -> PackageRequestStore.get(request_id) end) || {:error, :not_found},
         true <-
           PackageRequestPolicy.open?(request, today) || {:error, :package_request_closed},
         {:ok, _membership} <- ensure_membership(context, request.user_id),
         {:ok, received} <-
           Finance.with_tenant_context(context, fn ->
             ReceiveFinancePayment.call(context, request.user_id, admin_id, %{
               "purchase_package_id" => request.membership_package_id,
               "amount_cents" => request.price_cents_snapshot,
               "currency" => request.currency,
               "payment_method" => params["payment_method"],
               "notes" => params["notes"],
               "idempotency_key" => "package-request:" <> request.id
             })
           end),
         {:ok, closed} <- close_activated(context, request, received, admin_id) do
      {:ok, %{request: present(closed, today), received: received}}
    end
  end

  # A retry after the money was recorded finds the request already closed.
  defp close_activated(context, request, received, admin_id) do
    scoped(context, fn ->
      PackageRequestStore.close(request.id, "activated", %{
        closed_at: DateTime.utc_now(),
        closed_by_id: admin_id,
        membership_package_subscription_id: received[:membership_package_subscription_id],
        membership_payment_id: received.payment.id
      })
    end)
    |> case do
      {:ok, closed} ->
        {:ok, closed}

      {:error, {:package_request_closed, "activated"}} ->
        {:ok, Map.put(request, :status, "activated")}

      other ->
        other
    end
  end

  @doc """
  «Ενεργοποίηση» › «Εκκρεμεί πληρωμή»: the person trains from today and
  owes the package. Assigns it at the price they were shown, with its
  charge issued now (ADR-274 `billing: :now`), so the box's payment
  reminders, grace days and lock take over by themselves. Assigning closes
  the request as activated (ADR-291 addendum). A retry finds it closed.
  """
  def activate_unpaid(context, request_id, admin_id) do
    today = today(context)

    with %{} = request <-
           scoped(context, fn -> PackageRequestStore.get(request_id) end) || {:error, :not_found},
         true <-
           PackageRequestPolicy.open?(request, today) || {:error, :package_request_closed},
         {:ok, subscription} <-
           Finance.with_tenant_context(context, fn ->
             AssignFinanceMemberPackage.call(
               context,
               request.user_id,
               %{
                 "membership_package_id" => request.membership_package_id,
                 "signup_source" => "direct"
               },
               price_cents: request.price_cents_snapshot
             )
           end),
         {:ok, closed} <- close_unpaid(context, request, subscription, admin_id) do
      {:ok, %{request: present(closed, today), subscription_id: Map.get(subscription, :id)}}
    end
  end

  defp close_unpaid(context, request, subscription, admin_id) do
    scoped(context, fn ->
      case PackageRequestStore.get(request.id) do
        %{status: "activated"} = closed ->
          {:ok, closed}

        _pending ->
          PackageRequestStore.close(request.id, "activated", %{
            closed_at: DateTime.utc_now(),
            closed_by_id: admin_id,
            membership_package_subscription_id: Map.get(subscription, :id)
          })
      end
    end)
  end

  @doc """
  «Απόρριψη»: the desk will not activate it. The reason is required (at
  most 500 characters) and the person reads it in their notification. Their
  upcoming class while waiting, if any, is cancelled.
  """
  def decline(context, request_id, admin_id, params) do
    today = today(context)

    with {:ok, reason} <- decline_reason(params),
         {:ok, closed} <-
           scoped(context, fn ->
             PackageRequestStore.close(request_id, "declined", %{
               closed_at: DateTime.utc_now(),
               closed_by_id: admin_id,
               decline_reason: reason
             })
           end)
           |> closed_error() do
      cancelled = PackageRule.end_waiting(context, closed.user_id)
      notify_declined(context, closed, cancelled)
      {:ok, %{request: present(closed, today), cancelled_bookings: cancelled}}
    end
  end

  defp decline_reason(params) do
    case params |> Map.new(fn {key, value} -> {to_string(key), value} end) |> Map.get("reason") do
      reason when is_binary(reason) ->
        reason = String.trim(reason)

        cond do
          reason == "" -> {:error, :package_decline_reason_required}
          String.length(reason) > 500 -> {:error, :package_decline_reason_too_long}
          true -> {:ok, reason}
        end

      _missing ->
        {:error, :package_decline_reason_required}
    end
  end

  defp notify_declined(context, request, cancelled) do
    box =
      context.organization_id
      |> List.wrap()
      |> Palee.Application.PublicBox.boxes()
      |> List.first()

    Notifications.dispatch_event(:package_request_declined, %{
      organization_id: context.organization_id,
      user_id: request.user_id,
      package_request_id: request.id,
      package_name: request.package_name_snapshot,
      reason: request.decline_reason,
      cancelled_bookings: cancelled,
      box_name: box && box.name,
      box_slug: box && box.slug
    })
  end

  # Someone known to the box without a Finance profile yet: the profile the
  # payment needs, as a first online purchase creates it (ADR-248).
  defp ensure_membership(context, user_id) do
    case Finance.get_member_profile(context, user_id) do
      %{membership: %{} = membership} ->
        {:ok, membership}

      _none ->
        Finance.upsert_membership(context, user_id, %{
          user_type_snapshot: "member",
          status: "active",
          signup_source: "direct"
        })
    end
  end

  # ── Housekeeping ────────────────────────────────────────────────────────

  @doc """
  Closes as `lapsed` the requests whose 14 days ended. Returns how many.
  ADR-633: whoever booked their one class while waiting and still has no
  profile loses their upcoming bookings.
  """
  def lapse(context, now \\ DateTime.utc_now()) do
    today = Organizations.local_today(context.organization_id, now)
    lapsed = scoped(context, fn -> PackageRequestStore.lapse_before(today, now) end)

    lapsed
    |> Enum.map(& &1.user_id)
    |> Enum.uniq()
    |> Enum.each(&PackageRule.end_waiting(context, &1))

    length(lapsed)
  end

  # ── Shape ───────────────────────────────────────────────────────────────

  @doc "A request as the API shows it."
  def present(request, today) do
    %{
      id: request.id,
      user_id: request.user_id,
      package_id: request.membership_package_id,
      package_name: request.package_name_snapshot,
      price_cents: request.price_cents_snapshot,
      currency: request.currency,
      status: request.status,
      source: request.source,
      requested_at: request.inserted_at,
      hold_until: request.hold_until,
      hold_days: PackageRequestPolicy.hold_days(),
      days_left: PackageRequestPolicy.days_left(request, today),
      first_class_at: Map.get(request, :first_class_at),
      decline_reason: Map.get(request, :decline_reason)
    }
  end

  defp closed_error({:error, {:package_request_closed, _status}}),
    do: {:error, :package_request_closed}

  defp closed_error(other), do: other

  defp today(context), do: Organizations.local_today(context.organization_id)

  defp scoped(context, fun), do: PackageRequestStore.with_tenant_context(context, fun)

  defp cast_id(id) when is_binary(id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> {:ok, id}
      :error -> {:error, :not_found}
    end
  end

  defp cast_id(_id), do: {:error, :not_found}
end

defmodule Palee.Workers.SubscriptionExpiryJobTest do
  use Palee.DataCase, async: false
  use Oban.Testing, repo: Palee.Repo

  alias Palee.{Finance, Organizations, Repo}
  alias Palee.Application.AuthorizeFinanceEntitlement
  alias Palee.Scheduling.{Booking, ScheduledClass}
  alias Palee.TestFixtures
  alias Palee.Workers.SubscriptionExpiryJob

  setup do
    owner = TestFixtures.admin_fixture()
    member = TestFixtures.user_fixture(%{role: :member})
    context = tenant_context_fixture(owner, "Expiry Gym #{System.unique_integer([:positive])}")

    {:ok, membership} =
      Finance.upsert_membership(context, member.id, %{
        user_type_snapshot: "member",
        status: "active",
        signup_source: "direct"
      })

    {:ok, package} =
      Finance.create_package(context, %{
        code: "monthly-#{System.unique_integer([:positive])}",
        name: "Unlimited monthly",
        family: "unlimited",
        billing_period: "monthly",
        base_price_cents: 0
      })

    {:ok, subscription} =
      Finance.assign_package(context, membership.id, package.id, %{
        starts_on: Date.add(gym_today(), -27)
      })

    %{
      context: context,
      member: member,
      subscription: subscription,
      organization_id: context.organization_id
    }
  end

  defp end_subscription_on(subscription, ends_on) do
    Repo.query!("UPDATE membership_package_subscriptions SET ends_on = $1 WHERE id = $2", [
      ends_on,
      Ecto.UUID.dump!(subscription.id)
    ])
  end

  defp notifications(user_id) do
    %{rows: rows} =
      Repo.query!(
        "SELECT type, payload FROM notifications WHERE user_id = $1 ORDER BY inserted_at",
        [
          Ecto.UUID.dump!(user_id)
        ]
      )

    rows
  end

  test "reminds the client once before the subscription ends", ctx do
    end_subscription_on(ctx.subscription, Date.add(gym_today(), 3))

    assert :ok = perform_job(SubscriptionExpiryJob, %{})
    assert :ok = perform_job(SubscriptionExpiryJob, %{})

    assert [["subscription_expiring", payload]] = notifications(ctx.member.id)
    assert payload["days_left"] == 3
    assert payload["grace_days"] == 3
    assert payload["package_name"] == "Unlimited monthly"
  end

  test "a renewed subscription gets no reminder", ctx do
    end_subscription_on(ctx.subscription, Date.add(gym_today(), 3))

    Repo.query!(
      """
      INSERT INTO membership_package_subscriptions
        (id, organization_id, membership_id, membership_package_id, status, starts_on, ends_on,
         package_code_snapshot, package_family_snapshot, billing_period_snapshot, inserted_at, updated_at)
      SELECT gen_random_uuid(), organization_id, membership_id, membership_package_id, 'active',
             ends_on + 1, ends_on + 31, package_code_snapshot, package_family_snapshot,
             billing_period_snapshot, now(), now()
      FROM membership_package_subscriptions WHERE id = $1
      """,
      [Ecto.UUID.dump!(ctx.subscription.id)]
    )

    assert :ok = perform_job(SubscriptionExpiryJob, %{})
    assert notifications(ctx.member.id) == []
  end

  test "after the end the client keeps access during the grace days, then loses it", ctx do
    end_subscription_on(ctx.subscription, Date.add(gym_today(), -1))

    assert :ok = perform_job(SubscriptionExpiryJob, %{})
    assert [["subscription_grace", payload]] = notifications(ctx.member.id)
    assert payload["grace_until"] == Date.to_iso8601(Date.add(gym_today(), 2))

    assert %{status: "grace", source: "subscription_grace"} =
             Finance.get_effective_entitlement(ctx.context, ctx.member.id)

    end_subscription_on(ctx.subscription, Date.add(gym_today(), -5))

    assert %{status: "inactive"} = Finance.get_effective_entitlement(ctx.context, ctx.member.id)
  end

  test "when the slack is over every entitlement is revoked and upcoming bookings are cancelled",
       ctx do
    end_subscription_on(ctx.subscription, Date.add(gym_today(), -1))
    assert :ok = perform_job(SubscriptionExpiryJob, %{})

    class_type = Palee.TestFixtures.class_type_fixture(%{tenant_context: ctx.context})

    slot =
      Repo.insert!(%ScheduledClass{
        organization_id: ctx.organization_id,
        class_type_id: class_type.id,
        name: "Saturday WOD",
        scheduled_at: DateTime.add(DateTime.utc_now(), 3, :day) |> DateTime.truncate(:second),
        capacity: 10,
        master_workout_id:
          Palee.TestFixtures.workout_fixture(
            Palee.TestFixtures.admin_fixture(),
            %{tenant_context: ctx.context}
          ).id
      })

    booking =
      Repo.insert!(%Booking{
        organization_id: ctx.organization_id,
        scheduled_class_id: slot.id,
        user_id: ctx.member.id,
        status: :approved
      })

    # Grace is over.
    end_subscription_on(ctx.subscription, Date.add(gym_today(), -5))
    assert :ok = perform_job(SubscriptionExpiryJob, %{})

    assert Repo.get(Booking, booking.id) == nil
    assert ["subscription_grace", "access_ended"] = Enum.map(notifications(ctx.member.id), &hd/1)

    assert [_, ["access_ended", %{"cancelled_bookings" => 1, "reason" => "subscription_ended"}]] =
             notifications(ctx.member.id)

    actor = %{id: ctx.member.id, role: :member}

    for request <- [
          %{channel: :in_person, capability: :book_classes},
          %{channel: :in_person, capability: :execute_class_workouts},
          %{channel: :workout_library, capability: :execute_library_workouts},
          %{channel: :personal_programming, capability: :execute_assigned_workouts}
        ] do
      assert {:error, :finance_entitlement_inactive} =
               AuthorizeFinanceEntitlement.call(ctx.context, actor, request)
    end

    # Nothing more to revoke on the next run.
    assert :ok = perform_job(SubscriptionExpiryJob, %{})
    assert length(notifications(ctx.member.id)) == 2
  end

  describe "the box's reminder schedule (ADR-500)" do
    defp days_ago(days),
      do: DateTime.add(DateTime.utc_now(), -days * 86_400 - 60, :second)

    defp set_sent(subscription, field, at) do
      Repo.query!(
        "UPDATE membership_package_subscriptions SET #{field} = $1 WHERE id = $2",
        [at, Ecto.UUID.dump!(subscription.id)]
      )
    end

    test "reminds on the day the subscription ends, once", ctx do
      end_subscription_on(ctx.subscription, gym_today())

      assert :ok = perform_job(SubscriptionExpiryJob, %{})
      assert :ok = perform_job(SubscriptionExpiryJob, %{})

      # The "days before" reminder does not fire on the end day too.
      assert [["subscription_expiring", payload]] = notifications(ctx.member.id)
      assert payload["days_left"] == 0
    end

    test "the reminder before the end and the end-day one both arrive", ctx do
      end_subscription_on(ctx.subscription, Date.add(gym_today(), 1))
      assert :ok = perform_job(SubscriptionExpiryJob, %{})

      end_subscription_on(ctx.subscription, gym_today())
      assert :ok = perform_job(SubscriptionExpiryJob, %{})

      assert [1, 0] =
               Enum.map(notifications(ctx.member.id), fn [_type, payload] ->
                 payload["days_left"]
               end)
    end

    test "the day after names no access date when the box gives no grace days", ctx do
      {:ok, _} = Finance.update_finance_settings(ctx.context, %{subscription_grace_days: 0})
      end_subscription_on(ctx.subscription, Date.add(gym_today(), -1))

      assert :ok = perform_job(SubscriptionExpiryJob, %{})

      assert [["subscription_grace", payload]] =
               Enum.filter(notifications(ctx.member.id), &(hd(&1) == "subscription_grace"))

      assert payload["grace_until"] == nil
      assert payload["ends_on"] == Date.to_iso8601(Date.add(gym_today(), -1))
    end

    test "the box can turn off the end-day and day-after reminders", ctx do
      {:ok, _} =
        Finance.update_finance_settings(ctx.context, %{
          subscription_end_day_reminder: false,
          subscription_day_after_reminder: false
        })

      end_subscription_on(ctx.subscription, gym_today())
      assert :ok = perform_job(SubscriptionExpiryJob, %{})
      # Only the "days before" reminder, which now also covers the end day.
      assert [["subscription_expiring", %{"days_left" => 0}]] = notifications(ctx.member.id)

      end_subscription_on(ctx.subscription, Date.add(gym_today(), -1))
      assert :ok = perform_job(SubscriptionExpiryJob, %{})
      assert length(notifications(ctx.member.id)) == 1
    end

    test "then every interval days until the member renews", ctx do
      {:ok, _} =
        Finance.update_finance_settings(ctx.context, %{payment_reminder_interval_days: 7})

      end_subscription_on(ctx.subscription, Date.add(gym_today(), -8))
      set_sent(ctx.subscription, "grace_notice_sent_at", days_ago(7))

      assert :ok = perform_job(SubscriptionExpiryJob, %{})
      assert :ok = perform_job(SubscriptionExpiryJob, %{})

      followups =
        Enum.filter(notifications(ctx.member.id), fn [_type, payload] -> payload["followup"] end)

      assert [["subscription_grace", payload]] = followups
      assert payload["grace_until"] == nil

      # Six days after the last one: not yet; seven: again.
      set_sent(ctx.subscription, "renewal_followup_sent_at", days_ago(6))
      assert :ok = perform_job(SubscriptionExpiryJob, %{})
      assert length(Enum.filter(notifications(ctx.member.id), &elem_followup?/1)) == 1

      # A week later (the per-day dedupe key is today's: the earlier row goes).
      Repo.query!("DELETE FROM notifications WHERE user_id = $1", [
        Ecto.UUID.dump!(ctx.member.id)
      ])

      set_sent(ctx.subscription, "renewal_followup_sent_at", days_ago(7))
      assert :ok = perform_job(SubscriptionExpiryJob, %{})
      assert length(Enum.filter(notifications(ctx.member.id), &elem_followup?/1)) == 1
    end

    test "a member who owes money gets the payment reminder instead of the follow-up", ctx do
      end_subscription_on(ctx.subscription, Date.add(gym_today(), -8))
      set_sent(ctx.subscription, "grace_notice_sent_at", days_ago(7))

      {:ok, invoice} =
        Finance.create_invoice(ctx.context, ctx.subscription.membership_id, %{
          amount_cents: 3_000,
          description: "Monthly",
          due_date: Date.add(gym_today(), -8)
        })

      {:ok, _} = Finance.issue_invoice(ctx.context, invoice.id, %{})

      assert :ok = perform_job(SubscriptionExpiryJob, %{})
      assert Enum.filter(notifications(ctx.member.id), &elem_followup?/1) == []
    end

    defp elem_followup?([_type, payload]), do: payload["followup"] == true
  end

  defp tenant_context_fixture(owner, name) do
    {:ok, organization} = Organizations.create_organization(%{name: name})

    {:ok, _membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: owner.id,
        role: :owner,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    {:ok, context} = Organizations.resolve_tenant_context(owner, organization.slug)
    context
  end
end

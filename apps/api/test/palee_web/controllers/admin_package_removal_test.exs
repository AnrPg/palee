defmodule PaleeWeb.AdminPackageRemovalTest do
  @moduledoc """
  ADR-660 over HTTP: staff remove a member's package completely. Staff who
  manage billing choose what happens to an unpaid invoice nobody paid
  anything on; the front desk removes but never writes a debt off. A minute
  of «Αναίρεση», then the removal settles and the member is told.
  """

  use PaleeWeb.ConnCase, async: false
  use Oban.Testing, repo: Palee.Repo

  import Ecto.Query
  import Palee.TestFixtures

  alias Palee.Application.PackageRemoval
  alias Palee.Notifications.Notification
  alias Palee.Scheduling.{Booking, ScheduledClass}
  alias Palee.Workers.NotificationEventJob
  alias Palee.{Finance, Organizations, Repo}

  setup %{conn: conn} do
    start_supervised!(
      {Oban, Keyword.put(Application.fetch_env!(:palee, Oban), :testing, :manual)}
    )

    owner = user_fixture()
    desk = user_fixture()
    member = user_fixture()

    {:ok, box} =
      Organizations.create_organization(%{name: "Box #{System.unique_integer([:positive])}"})

    add!(box, owner, [:owner, :coach])
    add!(box, desk, [:front_desk])
    add!(box, member, [:member])

    {:ok, staff} = Organizations.resolve_tenant_context(owner, box.slug)

    {:ok, package} =
      Finance.create_package(staff, %{
        code: "monthly-#{System.unique_integer([:positive])}",
        name: "Μηνιαίο",
        family: "unlimited",
        billing_period: "monthly",
        base_price_cents: 5_000
      })

    {:ok, membership} =
      Finance.upsert_membership(staff, member.id, %{
        user_type_snapshot: "member",
        status: "active",
        signup_source: "direct"
      })

    # ADR-274: the package is charged from the day it starts.
    {:ok, subscription} = Finance.assign_package(staff, membership.id, package.id, %{})

    %{
      conn: conn,
      owner: owner,
      desk: desk,
      member: member,
      box: box,
      staff: staff,
      membership: membership,
      subscription: subscription
    }
  end

  defp authed(conn, user), do: conn |> recycle() |> put_bearer_token(user)
  defp admin(ctx), do: "/api/org/#{ctx.box.slug}/admin/finance/members/#{ctx.member.id}"
  defp removal_path(ctx), do: "#{admin(ctx)}/subscriptions/#{ctx.subscription.id}/removal"

  defp profile(ctx), do: Finance.get_member_profile(ctx.staff, ctx.member.id)

  defp open_invoice(ctx) do
    [invoice] = Enum.filter(profile(ctx).invoices, &(&1.status in ["issued", "overdue"]))
    invoice
  end

  defp subscription(ctx),
    do: Enum.find(profile(ctx).package_subscriptions, &(&1.id == ctx.subscription.id))

  defp notifications(ctx) do
    for job <- all_enqueued(worker: NotificationEventJob),
        do: perform_job(NotificationEventJob, job.args)

    bypass_rls(fn ->
      Repo.all(
        from n in Notification,
          where: n.type == :package_removed and n.user_id == ^ctx.member.id,
          select: n.payload
      )
    end)
  end

  defp after_undo(removal),
    do: DateTime.add(Map.fetch!(removal, :undo_until), 2, :second)

  test "billing staff choose to void the untouched invoice; the member has no package and no access",
       ctx do
    invoice = open_invoice(ctx)

    preview =
      ctx.conn |> authed(ctx.owner) |> get(removal_path(ctx)) |> json_response(200)

    assert %{
             "package_name" => "Μηνιαίο",
             "may_write_off" => true,
             "untouched_invoices" => [%{"id" => invoice_id, "total_cents" => 5_000}],
             "kept_owed_cents" => 0,
             "paid_cents" => 0,
             "undo_seconds" => 60
           } = preview["removal"]

    assert invoice_id == invoice.id

    # No preselection: the choice is required.
    assert %{"code" => "invoice_choice_required"} =
             ctx.conn
             |> authed(ctx.owner)
             |> post(removal_path(ctx), %{})
             |> json_response(422)

    body =
      ctx.conn
      |> authed(ctx.owner)
      |> post(removal_path(ctx), %{
        invoice_choice: "void",
        reason: "Moved away",
        reason_shared: true
      })
      |> json_response(201)

    assert %{"invoice_choice" => "void", "voided_invoice_count" => 1} = body["removal"]

    membership = profile(ctx).membership
    assert membership.status_shown == "no_package"
    assert membership.entitlement_status == "inactive"
    assert subscription(ctx).status == "cancelled"
    assert Enum.find(profile(ctx).invoices, &(&1.id == invoice.id)).status == "void"

    # The box membership is not touched.
    assert Organizations.membership_standing(ctx.box.id, ctx.member.id) == :member

    # Nothing reaches the member before the undo minute closes.
    assert notifications(ctx) == []

    {:ok, removal} = removal_record(ctx, body["removal"]["id"])
    assert {:snooze, _seconds} = PackageRemoval.settle(%{organization_id: ctx.box.id}, removal.id)

    assert :ok =
             PackageRemoval.settle(
               %{organization_id: ctx.box.id},
               removal.id,
               after_undo(removal)
             )

    assert [payload] = notifications(ctx)
    assert payload["package_name"] == "Μηνιαίο"
    assert payload["reason"] == "Moved away"
    assert payload["body"] =~ "Moved away"

    # Settled: told once, and it can no longer be undone.
    assert :ok =
             PackageRemoval.settle(
               %{organization_id: ctx.box.id},
               removal.id,
               after_undo(removal)
             )

    assert [_one] = notifications(ctx)

    assert %{"code" => "removal_not_undoable"} =
             ctx.conn
             |> authed(ctx.owner)
             |> delete("#{admin(ctx)}/package-removals/#{removal.id}")
             |> json_response(409)
  end

  test "«Αναίρεση» within the minute gives the package and the invoice back", ctx do
    invoice = open_invoice(ctx)

    %{"removal" => %{"id" => removal_id}} =
      ctx.conn
      |> authed(ctx.owner)
      |> post(removal_path(ctx), %{invoice_choice: "void"})
      |> json_response(201)

    assert %{"removal" => %{"undone_at" => undone_at}} =
             ctx.conn
             |> authed(ctx.owner)
             |> delete("#{admin(ctx)}/package-removals/#{removal_id}")
             |> json_response(200)

    assert is_binary(undone_at)
    assert subscription(ctx).status == "active"

    assert Enum.find(profile(ctx).invoices, &(&1.id == invoice.id)).status in [
             "issued",
             "overdue"
           ]

    refute profile(ctx).membership.status_shown == "no_package"

    # An undone removal is never settled and the member hears nothing.
    {:ok, removal} = removal_record(ctx, removal_id)

    assert :ok =
             PackageRemoval.settle(
               %{organization_id: ctx.box.id},
               removal_id,
               after_undo(removal)
             )

    assert notifications(ctx) == []

    # The package can be removed again.
    assert ctx.conn
           |> authed(ctx.owner)
           |> post(removal_path(ctx), %{invoice_choice: "keep"})
           |> json_response(201)
  end

  test "the front desk removes the package but the unpaid invoice always stays owed", ctx do
    invoice = open_invoice(ctx)

    preview = ctx.conn |> authed(ctx.desk) |> get(removal_path(ctx)) |> json_response(200)
    assert preview["removal"]["may_write_off"] == false

    assert %{"code" => "write_off_not_allowed"} =
             ctx.conn
             |> authed(ctx.desk)
             |> post(removal_path(ctx), %{invoice_choice: "void"})
             |> json_response(403)

    assert %{"removal" => %{"invoice_choice" => "keep", "voided_invoice_count" => 0}} =
             ctx.conn
             |> authed(ctx.desk)
             |> post(removal_path(ctx), %{})
             |> json_response(201)

    assert Enum.find(profile(ctx).invoices, &(&1.id == invoice.id)).status in [
             "issued",
             "overdue"
           ]

    membership = profile(ctx).membership
    assert membership.status_shown == "no_package"
    # What is owed does not keep access open without the package.
    assert membership.entitlement_status == "inactive"
  end

  test "a partly paid invoice keeps what is left owed and its payment", ctx do
    invoice = open_invoice(ctx)

    {:ok, _payment} =
      Finance.record_payment(ctx.staff, ctx.membership.id, %{
        amount_cents: 2_000,
        currency: "EUR",
        payment_method: "cash",
        payment_status: "paid",
        finance_invoice_id: invoice.id
      })

    preview = ctx.conn |> authed(ctx.owner) |> get(removal_path(ctx)) |> json_response(200)

    assert %{"untouched_invoices" => [], "kept_owed_cents" => 3_000, "paid_cents" => 2_000} =
             preview["removal"]

    # Nothing to choose: there is no untouched invoice.
    assert %{"removal" => %{"invoice_choice" => nil}} =
             ctx.conn
             |> authed(ctx.owner)
             |> post(removal_path(ctx), %{})
             |> json_response(201)

    assert Enum.find(profile(ctx).invoices, &(&1.id == invoice.id)).status != "void"
  end

  test "someone who left loses the box with the package they kept", ctx do
    assert ctx.conn
           |> authed(ctx.owner)
           |> post("#{admin(ctx)}/leave", %{})
           |> json_response(200)

    today = Organizations.local_today(ctx.box.id)

    assert ctx.conn
           |> authed(ctx.owner)
           |> post(removal_path(ctx), %{invoice_choice: "keep"})
           |> json_response(201)

    membership = profile(ctx).membership
    assert membership.leaving_on == Date.add(today, -1)
    assert membership.status_shown == "former"

    # The box is no longer one of theirs: the package that kept it is gone.
    assert [] ==
             ctx.conn |> authed(ctx.member) |> get("/api/memberships") |> json_response(200)
  end

  test "a removed package cannot be removed twice and others' removals are not reachable", ctx do
    assert ctx.conn
           |> authed(ctx.owner)
           |> post(removal_path(ctx), %{invoice_choice: "keep"})
           |> json_response(201)

    assert %{"code" => "subscription_not_removable"} =
             ctx.conn
             |> authed(ctx.owner)
             |> post(removal_path(ctx), %{invoice_choice: "keep"})
             |> json_response(409)

    # A member cannot remove packages.
    assert ctx.conn
           |> authed(ctx.member)
           |> get(removal_path(ctx))
           |> json_response(403)
  end

  defp free_package!(ctx) do
    {:ok, free} =
      Finance.create_package(ctx.staff, %{
        code: "free-#{System.unique_integer([:positive])}",
        name: "Δωρεάν",
        package_type: "membership",
        base_price_cents: 0
      })

    free
  end

  defp active_subscriptions(ctx),
    do: Enum.filter(profile(ctx).package_subscriptions, &(&1.status == "active"))

  test "«Αλλαγή πακέτου» ends the paid package and its invoice, starts the new one, and nothing comes back",
       ctx do
    invoice = open_invoice(ctx)
    free = free_package!(ctx)

    body =
      ctx.conn
      |> authed(ctx.owner)
      |> post(removal_path(ctx), %{
        invoice_choice: "void",
        replacement_package_id: free.id,
        reason: "Test account"
      })
      |> json_response(201)

    assert %{
             "package_name" => "Μηνιαίο",
             "replacement_package_name" => "Δωρεάν",
             "replacement_subscription_id" => replacement_id,
             "voided_invoice_count" => 1
           } = body["removal"]

    # One package, the new one; the old one and its invoice are gone for good.
    assert [%{id: ^replacement_id, membership_package_id: free_id}] = active_subscriptions(ctx)
    assert free_id == free.id
    assert subscription(ctx).status == "cancelled"
    assert Enum.find(profile(ctx).invoices, &(&1.id == invoice.id)).status == "void"

    # The hourly run, today and on the days after, issues nothing again
    # (it used to bring the invoice and «Ληξιπρόθεσμο» back every day).
    today = Organizations.local_today(ctx.box.id)

    for day <- [today, Date.add(today, 1), Date.shift(today, month: 1)] do
      Finance.charge_due_subscriptions(ctx.staff, day)
    end

    assert Enum.all?(profile(ctx).invoices, &(&1.status == "void"))
    assert Finance.membership_outstanding_balance_cents(ctx.staff, ctx.membership.id) == 0
    assert profile(ctx).membership.status_shown == "comped"

    # The member hears that the package changed, and keeps their bookings.
    {:ok, removal} = removal_record(ctx, body["removal"]["id"])

    assert :ok =
             PackageRemoval.settle(
               %{organization_id: ctx.box.id},
               removal.id,
               after_undo(removal)
             )

    assert [payload] = notifications(ctx)
    assert payload["replacement_package_name"] == "Δωρεάν"
    assert payload["body"] =~ "Δωρεάν"
    assert payload["cancelled_bookings"] in [0, "0"]
  end

  test "«Αλλαγή πακέτου» to the same package starts it again from a clean slate", ctx do
    invoice = open_invoice(ctx)

    %{"removal" => %{"replacement_subscription_id" => replacement_id}} =
      ctx.conn
      |> authed(ctx.owner)
      |> post(removal_path(ctx), %{
        invoice_choice: "void",
        replacement_package_id: ctx.subscription.membership_package_id
      })
      |> json_response(201)

    assert [%{id: ^replacement_id}] = active_subscriptions(ctx)
    assert Enum.find(profile(ctx).invoices, &(&1.id == invoice.id)).status == "void"

    # Its first period is charged once, as for any new package.
    assert [charge] = Enum.filter(profile(ctx).invoices, &(&1.status in ["issued", "overdue"]))
    assert charge.membership_package_subscription_id == replacement_id
  end

  test "«Αναίρεση» of a change gives the old package back and takes the new one away", ctx do
    invoice = open_invoice(ctx)
    free = free_package!(ctx)

    %{"removal" => %{"id" => removal_id}} =
      ctx.conn
      |> authed(ctx.owner)
      |> post(removal_path(ctx), %{invoice_choice: "void", replacement_package_id: free.id})
      |> json_response(201)

    assert ctx.conn
           |> authed(ctx.owner)
           |> delete("#{admin(ctx)}/package-removals/#{removal_id}")
           |> json_response(200)

    assert [%{id: id}] = active_subscriptions(ctx)
    assert id == ctx.subscription.id

    assert Enum.find(profile(ctx).invoices, &(&1.id == invoice.id)).status in [
             "issued",
             "overdue"
           ]
  end

  test "a change to a package that does not exist or is inactive changes nothing", ctx do
    assert ctx.conn
           |> authed(ctx.owner)
           |> post(removal_path(ctx), %{
             invoice_choice: "void",
             replacement_package_id: Ecto.UUID.generate()
           })
           |> json_response(404)

    assert subscription(ctx).status == "active"
    assert open_invoice(ctx)
  end

  test "after the undo minute the member's upcoming bookings are cancelled and counted", ctx do
    booking = upcoming_booking!(ctx)

    preview = ctx.conn |> authed(ctx.owner) |> get(removal_path(ctx)) |> json_response(200)
    assert preview["removal"]["upcoming_bookings"] == 1

    %{"removal" => %{"id" => removal_id}} =
      ctx.conn
      |> authed(ctx.owner)
      |> post(removal_path(ctx), %{invoice_choice: "keep", reason: "Staff only"})
      |> json_response(201)

    # Still there during the undo minute.
    assert bypass_rls(fn -> Repo.get(Booking, booking.id) end)

    {:ok, removal} = removal_record(ctx, removal_id)

    assert :ok =
             PackageRemoval.settle(
               %{organization_id: ctx.box.id},
               removal_id,
               after_undo(removal)
             )

    refute bypass_rls(fn -> Repo.get(Booking, booking.id) end)
    assert [payload] = notifications(ctx)
    assert payload["cancelled_bookings"] == 1
    # The reason was not ticked for the member.
    assert payload["reason"] in [nil, ""]
    refute payload["body"] =~ "Staff only"
  end

  defp upcoming_booking!(ctx) do
    class_type = Palee.TestFixtures.class_type_fixture(%{tenant_context: ctx.staff})

    bypass_rls(fn ->
      slot =
        Repo.insert!(%ScheduledClass{
          organization_id: ctx.box.id,
          class_type_id: class_type.id,
          name: "Saturday WOD",
          scheduled_at: DateTime.add(DateTime.utc_now(), 3, :day) |> DateTime.truncate(:second),
          capacity: 10,
          master_workout_id:
            Palee.TestFixtures.workout_fixture(ctx.owner, %{tenant_context: ctx.staff}).id
        })

      Repo.insert!(%Booking{
        organization_id: ctx.box.id,
        scheduled_class_id: slot.id,
        user_id: ctx.member.id,
        status: :approved
      })
    end)
  end

  defp removal_record(ctx, id) do
    Finance.with_tenant_context(ctx.staff, fn ->
      case Repo.get(Palee.Finance.PackageRemoval, id) do
        nil -> {:error, :not_found}
        removal -> {:ok, removal}
      end
    end)
  end

  defp add!(organization, user, roles) do
    {:ok, _membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: user.id,
        role: hd(roles),
        roles: roles,
        status: :active,
        joined_at: DateTime.utc_now()
      })
  end
end

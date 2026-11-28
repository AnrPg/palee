defmodule Palee.Application.Finance.PackageStarts do
  @moduledoc """
  ADR-795: a package that waits for the member's first completed class or
  WOD starts here.

  What completes a session (the box's own day):

    * attendance recorded as «Ήρθε» (staff, self check-in, a QR scan);
    * a class that ended with the booking still approved and no «Δεν ήρθε»
      (the hourly sweep, `sweep/2`);
    * a result of the box's or coach's WOD finished or logged by the member.

  A package that changed while it waited goes to review: the member is told
  (bell and push), books nothing more, and starts it with «Το κατάλαβα»
  (`acknowledge/3`).
  """

  @behaviour Palee.DomainEvents.Handler

  require Logger

  alias Palee.{Finance, Notifications, Organizations, Scheduling}

  @impl true
  def handle_event(:attendance_recorded, %{status: "attended"} = event) do
    context = %{organization_id: event.organization_id}

    on =
      case Scheduling.get_slot(context, event.scheduled_class_id) do
        %{scheduled_at: %DateTime{} = at} -> Organizations.local_date(context, at)
        _slot -> Organizations.local_date(context, Map.get(event, :at) || DateTime.utc_now())
      end

    start(context, event.user_id, %{kind: "class", id: event.scheduled_class_id, on: on})
  end

  def handle_event(:workout_result_recorded, %{user_id: user_id} = event)
      when is_binary(user_id) do
    context = %{organization_id: event.organization_id}
    on = Organizations.local_date(context, Map.get(event, :at) || DateTime.utc_now())
    start(context, user_id, %{kind: "workout", id: Map.get(event, :workout_id), on: on})
  end

  def handle_event(_name, _event), do: :ok

  @doc """
  The hourly sweep of one box: every waiting package whose member finished a
  class since it was given (the class is over, nobody marked «Δεν ήρθε»).
  """
  def sweep(%{organization_id: organization_id} = context, now \\ DateTime.utc_now()) do
    context
    |> Finance.list_waiting_package_starts()
    |> Enum.group_by(fn {user_id, _subscription_id, _since} -> user_id end)
    |> Enum.each(fn {user_id, waiting} ->
      since = waiting |> Enum.map(&elem(&1, 2)) |> Enum.min(Date)

      case Scheduling.completed_member_classes(
             context,
             user_id,
             day_start(organization_id, since),
             now
           ) do
        [%{scheduled_class_id: class_id, scheduled_at: at} | _later] ->
          start(context, user_id, %{
            kind: "class",
            id: class_id,
            on: Organizations.local_date(context, at)
          })

        [] ->
          :ok
      end
    end)
  end

  @doc "«Το κατάλαβα»: the member saw what changed; the package starts today."
  def acknowledge(context, user_id, start_id) do
    with %{} = start <- own_start(context, user_id, start_id),
         {:ok, started} <- Finance.acknowledge_package_start(context, start.id, user_id) do
      Logger.info(
        "package_start_acknowledged organization_id=#{context.organization_id} " <>
          "user_id=#{user_id} start_id=#{start.id} severity=#{started.severity}"
      )

      {:ok, started}
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "The member's packages that wait or are in review at the box."
  def for_member(context, user_id),
    do: Finance.list_package_starts(context, %{user_id: user_id, statuses: ["waiting", "review"]})

  @doc "The waiting / in-review start of each listed subscription, by subscription id."
  def for_subscriptions(context, subscriptions) do
    case Enum.map(subscriptions, & &1.id) do
      [] ->
        %{}

      ids ->
        context
        |> Finance.list_package_starts(%{subscription_ids: ids, statuses: ["waiting", "review"]})
        |> Map.new(&{&1.subscription_id, present(&1)})
    end
  end

  @doc "A start as the member and staff see it (JSON-ready)."
  def present(nil), do: nil

  def present(start) do
    %{
      id: start.id,
      subscription_id: start.subscription_id,
      status: start.status,
      package_name: start.package_name,
      waiting_since: start.waiting_since,
      session_kind: start.session_kind,
      session_on: start.session_on,
      severity: start.severity,
      changes: start.changes || [],
      started_on: start.started_on,
      acknowledged_at: start.acknowledged_at
    }
  end

  defp own_start(context, user_id, start_id) do
    context
    |> Finance.list_package_starts(%{user_id: user_id, statuses: ["review"]})
    |> Enum.find(&(&1.id == start_id))
  end

  defp start(context, user_id, session) do
    with subscription_id when is_binary(subscription_id) <-
           Finance.waiting_subscription_for_session(
             context,
             user_id,
             source_context(session.kind),
             session.id
           ),
         {:ok, result} <- Finance.begin_package_start(context, subscription_id, session) do
      after_start(context, user_id, result)
    else
      nil -> :ok
      {:error, reason} -> log_failure(context, user_id, reason)
    end
  end

  defp source_context("class"), do: "scheduling"
  defp source_context(_kind), do: "workout"

  defp after_start(context, user_id, {:started, start}) do
    Logger.info(
      "package_started organization_id=#{context.organization_id} user_id=#{user_id} " <>
        "start_id=#{start.id} session=#{start.session_kind} on=#{start.started_on}"
    )

    :ok
  end

  defp after_start(context, user_id, {:review, start}) do
    box =
      context.organization_id
      |> List.wrap()
      |> Palee.Application.PublicBox.boxes()
      |> List.first() || %{}

    Notifications.process_event("package_start_review", %{
      organization_id: context.organization_id,
      user_id: user_id,
      start_id: start.id,
      box_name: Map.get(box, :name),
      box_slug: Map.get(box, :slug),
      package_name: start.package_name,
      severity: start.severity
    })

    :ok
  end

  defp after_start(_context, _user_id, :not_waiting), do: :ok

  defp log_failure(context, user_id, reason) do
    Logger.error(
      "package_start_failed organization_id=#{context.organization_id} user_id=#{user_id} " <>
        "reason=#{inspect(reason)}"
    )

    {:error, reason}
  end

  defp day_start(organization_id, %Date{} = day),
    do:
      Palee.TimeZones.ZonedTime.start_of_day(
        day,
        Organizations.organization_timezone(organization_id)
      )
end

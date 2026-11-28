defmodule Palee.Application.AuthorizeMemberDayWod do
  @moduledoc """
  ADR-805 (ANR, 2026-11-28): a box member may get their own WOD for a day
  from their profile (`personal` mode) without online programming. It is
  like telling a member who trains at the box to do a WOD made for them, so
  it follows the rules of a class booking, not of online programming:

    * the member booked a class that day: the booking already used its
      visit, so the WOD uses nothing more (`:booked_class`);
    * otherwise the package (or a grace or gift, ADR-612/633) must let them
      book a class that day, and the WOD uses **one class visit** of it
      (`:class_visit`), from the package's general visits, as a booking for
      that day would;
    * with no class visit to use, online programming or personal training
      still serve as before (ADR-225), so an online client keeps working.

  The visit is reserved before the assignment is written and consumed once it
  is (`AssignWorkout`), with an idempotency key per delivery and member.
  """

  alias Palee.Application.AuthorizeProgramming
  alias Palee.{Finance, Identity, Organizations, Scheduling}
  alias Palee.Finance.Domain.EntitlementPolicy

  @type grant :: :booked_class | :class_visit | :online_programming | :personal_training

  @doc """
  `{:ok, grant}` for one member on `date`, or
  `{:error, :member_wod_not_covered, %{user_id, nickname, reason}}`.
  """
  @spec grant(map(), String.t(), Date.t() | String.t() | nil) ::
          {:ok, grant()} | {:error, :member_wod_not_covered, map()}
  def grant(context, member_id, date) do
    date = to_date(context, date)

    cond do
      booked_on?(context, member_id, date) ->
        {:ok, :booked_class}

      class_visit?(context, member_id, date) ->
        {:ok, :class_visit}

      true ->
        case AuthorizeProgramming.grant_for(context, member_id) do
          {:ok, grant} -> {:ok, grant}
          {:error, _reason} -> denial(context, member_id, date)
        end
    end
  end

  @doc "`grant/3` for several members on one date: `{:ok, %{id => grant}}` or the first refusal."
  def grants(context, member_ids, date) do
    Enum.reduce_while(member_ids, {:ok, %{}}, fn id, {:ok, acc} ->
      case grant(context, id, date) do
        {:ok, grant} -> {:cont, {:ok, Map.put(acc, id, grant)}}
        error -> {:halt, error}
      end
    end)
  end

  @doc """
  For the profile: whether a personal WOD on a day without a booking would
  use a class visit (`true`) for this member today, i.e. their package lets
  them book classes.
  """
  def class_visits?(context, member_id), do: class_visit?(context, member_id, today(context))

  # The package itself must hold class visits (strict, whatever the tenant's
  # rollout mode: a role or a missing finance profile never implies it, as
  # for ADR-125), and Finance must let one more be used that day (limits,
  # freezes, package dates, grace).
  defp class_visit?(context, member_id, date) do
    request = visit_request(date)

    EntitlementPolicy.authorize_explicit(
      Finance.get_effective_entitlement(context, member_id),
      request
    ) == :ok and Finance.check_entitlements(context, member_id, [request]) == [:ok]
  end

  @doc "The Finance request of one class visit on `date` (general visits, no class type)."
  def visit_request(%Date{} = date) do
    %{
      channel: :in_person,
      capability: :book_classes,
      allowance: :class_visits,
      quantity: 1,
      occurred_on: date
    }
  end

  @doc "The reservation request a delivery takes for one member."
  def reservation_request(%Date{} = date, delivery_id, member_id) do
    date
    |> visit_request()
    |> Map.merge(%{
      source_context: "workouts",
      source_id: delivery_id,
      idempotency_key: "member-day-wod:#{delivery_id}:#{member_id}",
      metadata: %{"kind" => "member_day_wod", "date" => Date.to_iso8601(date)}
    })
  end

  @doc "The date an assignment is for (today when none is given), in the gym's own calendar."
  def to_date(_context, %Date{} = date), do: date

  def to_date(context, value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      {:error, _} -> today(context)
    end
  end

  def to_date(context, _missing), do: today(context)

  # A class the member booked on that gym day (pending or approved).
  defp booked_on?(context, member_id, %Date{} = date) do
    from = DateTime.new!(Date.add(date, -1), ~T[12:00:00], "Etc/UTC")
    to = DateTime.new!(Date.add(date, 1), ~T[12:00:00], "Etc/UTC")

    context
    |> Scheduling.list_member_slots(member_id, from, to)
    |> Enum.any?(fn slot ->
      case utc(Map.get(slot, :scheduled_at)) do
        %DateTime{} = at ->
          is_nil(Map.get(slot, :cancelled_at)) and Organizations.local_date(context, at) == date

        nil ->
          false
      end
    end)
  end

  defp utc(%DateTime{} = at), do: at
  defp utc(%NaiveDateTime{} = at), do: DateTime.from_naive!(at, "Etc/UTC")
  defp utc(_other), do: nil

  defp denial(context, member_id, date) do
    request = visit_request(date)

    reason =
      with :ok <-
             EntitlementPolicy.authorize_explicit(
               Finance.get_effective_entitlement(context, member_id),
               request
             ),
           [{:error, reason}] <- Finance.check_entitlements(context, member_id, [request]) do
        to_string(reason)
      else
        {:error, reason} -> to_string(reason)
        _other -> "no_class_visit"
      end

    nickname =
      case Identity.find_by_id(member_id) do
        %{nickname: nickname} when is_binary(nickname) -> nickname
        _ -> nil
      end

    {:error, :member_wod_not_covered,
     %{user_id: member_id, nickname: nickname, date: Date.to_iso8601(date), reason: reason}}
  end

  defp today(context), do: Organizations.local_today(context.organization_id)
end

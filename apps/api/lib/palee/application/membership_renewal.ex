defmodule Palee.Application.MembershipRenewal do
  @moduledoc """
  ADR-220: the member decides whether their subscription renews, and can
  leave the box; staff can do both for them and mark someone as left.

  Turning renewal off (or leaving) never takes away a paid period: the
  subscription runs to its last day and then ends through the usual expiry
  flow. Only unpaid invoices for periods after that day (or for packages
  that never started) are voided; anything already used stays owed and
  keeps its payment reminders until it is paid. Staff who manage
  billing hear when a member leaves.

  ADR-595: leaving ends the box membership at once (the person may join
  another box, or this one again, whenever they like); only the package they
  already have keeps them reaching the box, until its last day.
  """

  alias Palee.{Finance, Identity, Notifications, Organizations}

  @doc "The member turns renewal of one of their subscriptions on or off."
  def member_set_auto_renew(%{user_id: user_id} = context, subscription_id, auto_renew)
      when is_boolean(auto_renew),
      do:
        Finance.set_subscription_auto_renew(
          context,
          user_id,
          subscription_id,
          auto_renew,
          "member"
        )

  def member_set_auto_renew(_context, _subscription_id, _auto_renew),
    do: {:error, :invalid_auto_renew}

  @doc """
  ADR-595: the member leaves the box. Their box membership ends now; a
  package they already have stays usable to its last day (no renewal, and a
  minimum commitment stays owed), money owed stays owed and reminded, and
  following the box is untouched. Staff who manage billing hear of it.
  """
  def member_leave(%{user_id: user_id} = context, params) do
    with {:ok, result} <- end_membership(context, user_id, "member", params) do
      notify_staff(context, user_id, result)
      {:ok, result}
    end
  end

  @doc "Staff turn a member's renewal on or off (for example, asked at the desk)."
  def staff_set_auto_renew(context, user_id, subscription_id, auto_renew)
      when is_boolean(auto_renew),
      do:
        Finance.set_subscription_auto_renew(
          context,
          user_id,
          subscription_id,
          auto_renew,
          "staff"
        )

  def staff_set_auto_renew(_context, _user_id, _subscription_id, _auto_renew),
    do: {:error, :invalid_auto_renew}

  @doc """
  ADR-595: staff end someone's box membership, with the member's own rules:
  it ends now, the package runs to its natural last day, what is owed stays
  owed. The person hears that the box ended it.
  """
  def staff_mark_left(context, user_id, params) when is_map(params) do
    with {:ok, result} <- end_membership(context, user_id, "staff", params) do
      notify_member(context, user_id, result)
      {:ok, result}
    end
  end

  @doc "Staff undo a leave (it was a mistake): the person is a member again."
  def staff_undo_leave(%{organization_id: organization_id} = context, user_id) do
    with {:ok, membership} <- Finance.undo_leave_membership(context, user_id, "staff"),
         {:ok, _box_membership} <- Organizations.undo_box_membership_end(organization_id, user_id) do
      {:ok, membership}
    end
  end

  @doc """
  ADR-595: someone who left came back (any way in clears the box side): their
  finance profile stops leaving, so renewals resume and the status follows.
  """
  def rejoined(organization_id, user_id) when is_binary(organization_id) and is_binary(user_id),
    do:
      Finance.rejoin_after_leaving(%{organization_id: organization_id, user_id: user_id}, user_id)

  @doc "The day a member leaving today would keep access until, or nil."
  def leave_preview(%{user_id: user_id} = context),
    do: Finance.membership_leave_preview(context, user_id)

  defp notify_staff(%{organization_id: organization_id}, user_id, result) do
    person = Identity.find_by_id(user_id)
    left_at = result.box_membership_ended_at || DateTime.utc_now()

    Notifications.dispatch_event(:member_leaving, %{
      organization_id: organization_id,
      member_user_id: user_id,
      person_nickname: person && person.nickname,
      leaving_on: Date.to_iso8601(result.leaving_on || DateTime.to_date(left_at)),
      reason: result.membership && Map.get(result.membership, :leave_reason),
      left_at: DateTime.to_unix(left_at, :microsecond)
    })
  end

  # The finance side first (it decides the last day), then the box side. A
  # retry after the second step failed finds the finance side already
  # leaving and completes the box side with its day.
  defp end_membership(%{organization_id: organization_id} = context, user_id, by, params) do
    finance =
      case Finance.leave_membership(context, user_id, %{"by" => by, "reason" => reason(params)}) do
        {:ok, result} -> {:ok, result}
        {:error, :member_leaving} -> already_leaving(context, user_id)
        # No finance profile: nothing bought, nothing owed.
        {:error, :not_found} -> {:ok, %{membership: nil, leaving_on: nil, outstanding_cents: 0}}
        error -> error
      end

    with {:ok, result} <- finance,
         {:ok, box_membership} <-
           Organizations.end_box_membership(organization_id, user_id, by, result.leaving_on) do
      {:ok, Map.put(result, :box_membership_ended_at, box_membership.left_at)}
    end
  end

  defp already_leaving(context, user_id) do
    case Finance.get_member_profile(context, user_id) do
      %{membership: %{leaving_on: %Date{} = leaving_on} = membership} ->
        if Organizations.membership_standing(context.organization_id, user_id) == :former,
          do: {:error, :member_leaving},
          else: {:ok, %{membership: membership, leaving_on: leaving_on, outstanding_cents: nil}}

      _other ->
        {:error, :member_leaving}
    end
  end

  defp notify_member(%{organization_id: organization_id} = context, user_id, result) do
    organization = Map.get(context, :organization) || %{}

    Notifications.dispatch_event(:box_membership_ended, %{
      organization_id: organization_id,
      user_id: user_id,
      box_name: Map.get(organization, :name),
      box_slug: Map.get(organization, :slug),
      access_until: result.leaving_on && Date.to_iso8601(result.leaving_on),
      left_at:
        DateTime.to_unix(result.box_membership_ended_at || DateTime.utc_now(), :microsecond)
    })
  end

  defp reason(params) when is_map(params) do
    case Map.get(params, "reason") do
      value when is_binary(value) -> String.slice(value, 0, 500)
      _other -> nil
    end
  end

  defp reason(_params), do: nil
end

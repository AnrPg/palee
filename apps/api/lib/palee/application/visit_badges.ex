defmodule Palee.Application.VisitBadges do
  @moduledoc """
  ADR-359 (CP-E1): «Πρώτη επίσκεψη», «Επισκέπτης» and the other visit
  badges on a class list and at the check-in desk
  (`Scheduling.Domain.VisitBadges`).

  `for_class/2` badges every live seat of a class (pending, approved and
  waitlisted), counting visits before the class starts and never the class
  itself. `for_person/4` badges one person at the desk at `now`. A guest
  pass seat («brought by a member») carries only that badge: the history
  read is the member's, not the guest's.

  Staff only (route capabilities `run_classes`, `check_in`,
  `manage_schedule`); branch-scoped staff only for their branches.
  """

  alias Palee.{Identity, Organizations, Scheduling}
  alias Palee.Scheduling.VisitFactsStore

  @live ~w(pending approved waitlisted)

  def for_class(%{organization_id: org} = context, slot_id) when is_binary(org) do
    with %{} = slot <- Scheduling.get_slot(context, slot_id) || {:error, :not_found},
         :ok <- Organizations.authorize_location(context, Map.get(slot, :location_id)) do
      seats = Enum.filter(slot.bookings || [], &(to_string(&1.status) in @live))
      member_ids = seats |> Enum.reject(&guest_pass?/1) |> Enum.map(& &1.user_id) |> Enum.uniq()

      facts =
        facts(context, member_ids, slot.scheduled_at, slot.class_type_id, [slot.id])

      people = people(Enum.map(seats, & &1.user_id))

      {:ok,
       %{
         slot_id: slot.id,
         people:
           Enum.map(seats, fn booking ->
             badges =
               if guest_pass?(booking),
                 do: ["brought_by_member"],
                 else:
                   facts
                   |> Map.get(booking.user_id, %{})
                   |> Map.put(:booking_kind, booking.kind)
                   |> Scheduling.visit_badges()

             %{
               booking_id: booking.id,
               user_id: booking.user_id,
               guest_name: blank_to_nil(booking.guest_name),
               brought_by: brought_by(booking, people),
               badges: badges,
               via: via(Map.get(facts, booking.user_id), people)
             }
           end)
       }}
    end
  end

  def for_class(_context, _slot_id), do: {:error, :organization_context_required}

  @doc "The badges of one person at the desk; `class_type_id` of the class they check in to."
  def for_person(%{organization_id: _} = context, user_id, now, opts \\ []) do
    class_type_id = Keyword.get(opts, :class_type_id)
    exclude = Keyword.get(opts, :exclude_class_ids, [])
    facts = context |> facts([user_id], now, class_type_id, exclude) |> Map.get(user_id, %{})

    %{
      badges: facts |> Map.put(:booking_kind, Keyword.get(opts, :booking_kind)) |> Scheduling.visit_badges(),
      via: via(facts, people(referrer_ids([facts])))
    }
  end

  defp facts(_context, [], _before, _type, _exclude), do: %{}

  defp facts(context, user_ids, before, class_type_id, exclude) do
    counts = VisitFactsStore.visit_counts(context, user_ids, before, class_type_id, exclude)
    referrals = VisitFactsStore.referrals(context, user_ids)

    Map.new(user_ids, fn user_id ->
      summary = Organizations.membership_summary(context.organization_id, user_id)

      {user_id,
       counts
       |> Map.get(user_id, %{box_visits: 0, type_visits: nil})
       |> Map.merge(%{
         roles: (summary && summary.roles) || [],
         referral: Map.get(referrals, user_id)
       })}
    end)
  end

  defp via(%{referral: %{} = referral, box_visits: 0}, people) do
    %{
      kind: if(referral.event_id, do: "event", else: "referral"),
      event_id: referral.event_id,
      channel: referral.channel,
      by_user_id: referral.referrer_user_id,
      by_nickname: people |> Map.get(referral.referrer_user_id, %{}) |> Map.get(:nickname)
    }
  end

  defp via(_facts, _people), do: nil

  defp referrer_ids(facts) do
    for %{referral: %{referrer_user_id: id}} <- facts, is_binary(id), do: id
  end

  defp brought_by(booking, people) do
    if guest_pass?(booking) do
      person = Map.get(people, booking.user_id, %{})
      %{user_id: booking.user_id, nickname: Map.get(person, :nickname)}
    end
  end

  defp guest_pass?(booking),
    do: booking.kind == "guest" or blank_to_nil(booking.guest_name) != nil

  defp people([]), do: %{}
  defp people(ids), do: ids |> Enum.uniq() |> Identity.list_by_ids() |> Map.new(&{&1.id, &1})

  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: value
end

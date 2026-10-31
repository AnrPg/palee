defmodule Palee.Scheduling.Domain.VisitBadges do
  @moduledoc """
  ADR-359 (CP-E1): the badges staff see next to a person on a class list
  and at check-in, so the coach knows whom to welcome and what to say.

    * `first_visit` – no earlier visit to the box (an attended or approved
      class that already took place, or a check-in);
    * `first_in_class_type` – visited the box before, never this kind of
      class;
    * `guest` – the person is only a guest of the box («Επισκέπτης»,
      ADR-272): a box role, not a booking kind;
    * `trial` – the seat is a trial (ADR-144);
    * `brought_by_member` – a member's guest pass (the booking carries the
      guest's name, the member is the one who booked);
    * `came_via_event` / `came_via_referral` – how the person first came,
      from their referral attribution (`via` says who or which event).

  Order is the order a coach reads them: who is new first.
  """

  @order ~w(first_visit first_in_class_type guest trial brought_by_member came_via_event came_via_referral)

  def all, do: @order

  @type facts :: %{
          optional(:box_visits) => non_neg_integer(),
          optional(:type_visits) => non_neg_integer() | nil,
          optional(:roles) => [String.t()],
          optional(:booking_kind) => String.t() | nil,
          optional(:guest_name) => String.t() | nil,
          optional(:referral) => %{channel: String.t() | nil, event_id: String.t() | nil} | nil
        }

  @doc "The badges of one person, in reading order."
  @spec badges(facts()) :: [String.t()]
  def badges(facts) do
    box_visits = Map.get(facts, :box_visits, 0)
    type_visits = Map.get(facts, :type_visits)
    roles = Map.get(facts, :roles) || []
    kind = Map.get(facts, :booking_kind)
    guest_name = Map.get(facts, :guest_name)
    first? = box_visits == 0

    [
      {"first_visit", first?},
      {"first_in_class_type", not first? and type_visits == 0},
      {"guest", guest_only?(roles)},
      {"trial", kind == "trial"},
      {"brought_by_member", kind == "guest" or (is_binary(guest_name) and guest_name != "")},
      {"came_via_event", first? and event?(Map.get(facts, :referral))},
      {"came_via_referral", first? and referral?(Map.get(facts, :referral))}
    ]
    |> Enum.filter(&elem(&1, 1))
    |> Enum.map(&elem(&1, 0))
  end

  defp guest_only?(roles) do
    roles = Enum.map(roles, &to_string/1)
    "guest" in roles and Enum.all?(roles, &(&1 == "guest"))
  end

  defp event?(%{event_id: id}) when is_binary(id), do: true
  defp event?(_referral), do: false

  defp referral?(%{event_id: id}) when is_binary(id), do: false
  defp referral?(%{referrer_user_id: id}) when is_binary(id), do: true
  defp referral?(_referral), do: false
end

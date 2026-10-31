defmodule Palee.Application.Access.DoorAccess do
  @moduledoc """
  Opening a door (ADR-381, CP-E3) and the controllers' own events.

  A member proves presence exactly as for the QR check-in (ADR-155): the
  door screen's rotating code, the branch's NFC tag or the printed poster
  (`ScanCheckIn.door_presence/3`). Then `EntryRules` decides on facts
  gathered now (staff, membership, bookings in the window, open-gym
  coverage) and the box's local time, the controller is asked to open, and
  every outcome goes into the access log:

    * `granted` – opened; the answer names the door and the reason;
    * `denied` – `entry_denied` with the reason (`not_a_member`,
      `outside_hours`, `no_booking_in_window`, `staff_only`);
    * `unlock_failed` – the controller could not be reached
      (`door_offline`): the door stays locked and the app sends the member
      to the desk. Nothing is retried later (fail-secure).

  Opening never checks a member in: the app does both from one scan, and
  the box sees each in its own log.
  """

  alias Palee.Access
  alias Palee.Application.{CheckInFacts, ScanCheckIn}
  alias Palee.Organizations
  alias Palee.Organizations.Domain.MembershipPolicy
  alias Palee.TimeZones.ZonedTime

  @doc """
  `params`: what the door scan takes (`location_id` + `code`, `nfc_code` or
  `poster_code`) and optionally `door_id` when a branch has several doors.
  """
  def open(%{id: user_id}, params, now \\ DateTime.utc_now()) do
    with {:ok, presence} <- ScanCheckIn.door_presence(user_id, params, now),
         context = %{organization_id: presence.organization_id, user_id: user_id},
         {:ok, door} <- pick_door(context, presence.location_id, param(params, :door_id)) do
      facts = facts(context, user_id, presence.location_id, now)
      local = local_time(context, now)
      method = method(presence.source)

      case Access.decide(door, facts, now, local) do
        {:grant, reason} -> unlock(context, door, user_id, reason, method, now)
        {:deny, reason} -> deny(context, door, user_id, reason, method, now)
      end
    end
  end

  defp unlock(context, door, user_id, reason, method, now) do
    case Access.unlock(context, door, now) do
      :ok ->
        log(context, door, user_id, "granted", reason, method, now)

        {:ok,
         %{
           opened: true,
           reason: Atom.to_string(reason),
           door: %{id: door.id, name: door.name},
           seconds: Map.get(door.rules, "unlock_seconds", 5)
         }}

      {:error, failure} ->
        log(context, door, user_id, "unlock_failed", failure, method, now)
        {:error, failure}
    end
  end

  defp deny(context, door, user_id, reason, method, now) do
    log(context, door, user_id, "denied", reason, method, now)
    {:error, :entry_denied, %{reason: Atom.to_string(reason), door: %{id: door.id, name: door.name}}}
  end

  defp pick_door(context, location_id, door_id) do
    case {Access.doors_at(context, location_id), door_id} do
      {[], _id} ->
        {:error, :no_door_here}

      {[door], nil} ->
        {:ok, door}

      {doors, nil} ->
        {:error, :choose_door, %{doors: Enum.map(doors, &%{id: &1.id, name: &1.name})}}

      {doors, id} ->
        case Enum.find(doors, &(&1.id == id)) do
          nil -> {:error, :no_door_here}
          door -> {:ok, door}
        end
    end
  end

  defp facts(context, user_id, location_id, now) do
    gathered = CheckInFacts.gather(context, user_id, location_id, now)
    roles = context |> Organizations.member_roles_by_user() |> Map.get(user_id, %{}) |> Map.get(:roles, [])

    %{
      staff?: gathered.member? and MembershipPolicy.staff?(roles),
      member?: gathered.member?,
      bookings: gathered.bookings,
      open_gym_covered?: get_in(gathered, [:open_gym, :covered?]) == true,
      location_id: location_id
    }
  end

  defp local_time(%{organization_id: organization_id}, now) do
    now
    |> ZonedTime.local(Organizations.organization_timezone(organization_id))
    |> DateTime.to_naive()
  end

  defp method(:nfc), do: "nfc"
  defp method(_qr), do: "qr"

  defp log(context, door, user_id, kind, reason, method, now) do
    Access.record(context, %{
      door_controller_id: door.id,
      location_id: door.location_id,
      user_id: user_id,
      kind: kind,
      reason: to_string(reason),
      method: method,
      occurred_at: now
    })
  end

  @doc """
  A door controller's own notification (`POST /api/access/doors/:id/events`
  with the door's event token): `{:ok, %{recorded: n}}` or `{:error,
  :not_found}`.
  """
  def ingest(door_id, token, params, now \\ DateTime.utc_now()) do
    with {:ok, count} <- Access.ingest_event(door_id, token, params, now),
         do: {:ok, %{recorded: count}}
  end

  defp param(params, key), do: Map.get(params, key) || Map.get(params, Atom.to_string(key))
end

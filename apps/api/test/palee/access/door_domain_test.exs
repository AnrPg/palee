defmodule Palee.Access.DoorDomainTest do
  @moduledoc "ADR-381: who may open a door when, and what each controller needs."

  use ExUnit.Case, async: true

  alias Palee.Access.Domain.{EntryRules, ProviderSettings}

  @now ~U[2026-11-02 05:30:00Z]
  # 07:30 in Athens (UTC+2), a Monday.
  @local ~N[2026-11-02 07:30:00]

  defp facts(overrides \\ %{}) do
    Map.merge(
      %{staff?: false, member?: true, bookings: [], open_gym_covered?: false, location_id: "l1"},
      overrides
    )
  end

  defp booking(minutes_from_now, location_id \\ "l1"),
    do: %{starts_at: DateTime.add(@now, minutes_from_now * 60, :second), location_id: location_id}

  describe "decide/4" do
    test "staff always, unless the door says otherwise" do
      assert {:grant, :staff} = EntryRules.decide(facts(%{staff?: true}), %{}, @now, @local)

      assert {:deny, :staff_only} =
               EntryRules.decide(
                 facts(%{staff?: true}),
                 %{"staff_always" => false, "who" => "staff_only"},
                 @now,
                 @local
               )
    end

    test "not a member is never let in" do
      assert {:deny, :not_a_member} =
               EntryRules.decide(facts(%{member?: false}), %{"who" => "members"}, @now, @local)
    end

    test "a booking at this branch within 30 minutes before to 15 after its start opens the door" do
      assert {:grant, :booked_class} =
               EntryRules.decide(facts(%{bookings: [booking(30)]}), %{}, @now, @local)

      assert {:grant, :booked_class} =
               EntryRules.decide(facts(%{bookings: [booking(-15)]}), %{}, @now, @local)

      assert {:deny, :no_booking_in_window} =
               EntryRules.decide(facts(%{bookings: [booking(31)]}), %{}, @now, @local)

      assert {:deny, :no_booking_in_window} =
               EntryRules.decide(facts(%{bookings: [booking(-16)]}), %{}, @now, @local)

      assert {:deny, :no_booking_in_window} =
               EntryRules.decide(facts(%{bookings: [booking(5, "l2")]}), %{}, @now, @local)

      assert {:grant, :booked_class} =
               EntryRules.decide(
                 facts(%{bookings: [booking(50)]}),
                 %{"window_before_minutes" => 60},
                 @now,
                 @local
               )
    end

    test "open gym cover opens it too; members-only doors admit every active member" do
      assert {:grant, :open_gym} =
               EntryRules.decide(facts(%{open_gym_covered?: true}), %{}, @now, @local)

      assert {:grant, :member} = EntryRules.decide(facts(), %{"who" => "members"}, @now, @local)

      assert {:deny, :staff_only} =
               EntryRules.decide(facts(), %{"who" => "staff_only"}, @now, @local)
    end

    test "opening hours are in the box's local time" do
      hours = [%{"days" => [1, 2, 3, 4, 5], "from" => "06:00", "to" => "22:00"}]

      assert {:grant, :member} =
               EntryRules.decide(facts(), %{"who" => "members", "hours" => hours}, @now, @local)

      assert {:deny, :outside_hours} =
               EntryRules.decide(
                 facts(),
                 %{"who" => "members", "hours" => hours},
                 @now,
                 ~N[2026-11-02 05:59:00]
               )

      # Sunday.
      assert {:deny, :outside_hours} =
               EntryRules.decide(
                 facts(),
                 %{"who" => "members", "hours" => hours},
                 @now,
                 ~N[2026-11-01 10:00:00]
               )
    end
  end

  describe "normalize/1" do
    test "fills defaults and refuses nonsense" do
      assert {:ok, rules} = EntryRules.normalize(%{who: "members", unknown: 1})
      assert rules["who"] == "members"
      assert rules["unlock_seconds"] == 5
      refute Map.has_key?(rules, "unknown")

      assert {:ok, %{"hours" => [%{"days" => [1, 2], "from" => "06:00", "to" => "24:00"}]}} =
               EntryRules.normalize(%{
                 "hours" => [%{"days" => [2, 1, 1], "from" => "06:00", "to" => "24:00"}]
               })

      for bad <- [
            %{"who" => "everyone"},
            %{"unlock_seconds" => 0},
            %{"window_before_minutes" => 500},
            %{"staff_always" => "yes"},
            %{"hours" => [%{"days" => [8], "from" => "06:00", "to" => "07:00"}]},
            %{"hours" => [%{"days" => [1], "from" => "09:00", "to" => "08:00"}]},
            %{"hours" => [%{"days" => [1], "from" => "9", "to" => "10:00"}]}
          ] do
        assert {:error, :invalid_door_rules} = EntryRules.normalize(bad), inspect(bad)
      end
    end
  end

  describe "provider settings" do
    test "Shelly needs its cloud server, device, channel and auth key" do
      assert {:ok,
              %{
                "server" => "shelly-77-eu.shelly.cloud",
                "device_id" => "a8032ab12345",
                "channel" => 0
              },
              %{"auth_key" => _key}} =
               ProviderSettings.validate(
                 "shelly",
                 %{
                   "server" => "https://Shelly-77-eu.shelly.cloud",
                   "device_id" => "a8032ab12345"
                 },
                 %{"auth_key" => String.duplicate("k", 40)}
               )

      assert {:error, :invalid_door_settings} =
               ProviderSettings.validate(
                 "shelly",
                 %{"server" => "evil.example.com", "device_id" => "a8032ab12345"},
                 %{"auth_key" => String.duplicate("k", 40)}
               )

      assert {:error, :invalid_door_settings} =
               ProviderSettings.validate(
                 "shelly",
                 %{"server" => "x.shelly.cloud", "device_id" => "a8032ab12345", "channel" => 4},
                 %{"auth_key" => String.duplicate("k", 40)}
               )
    end

    test "a saved key is kept when none is sent" do
      assert {:ok, %{"lock_id" => 42}, %{"api_key" => "saved-key-0123456789"}} =
               ProviderSettings.validate("kisi", %{"lock_id" => "42"}, nil, %{
                 "api_key" => "saved-key-0123456789"
               })

      assert {:error, :invalid_door_settings} =
               ProviderSettings.validate("kisi", %{"lock_id" => 42}, nil)

      assert {:error, :invalid_door_settings} = ProviderSettings.validate("nuki", %{}, %{})
    end
  end
end

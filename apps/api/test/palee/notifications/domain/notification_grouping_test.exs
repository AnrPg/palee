defmodule Palee.Notifications.Domain.NotificationGroupingTest do
  use ExUnit.Case, async: true

  alias Palee.Notifications.Domain.NotificationGrouping, as: Grouping

  @box "6a0e3c2e-0000-4000-8000-000000000001"
  @day ~D[2026-11-10]

  describe "rule/1" do
    test "every type not named stacks by type, box and day" do
      assert Grouping.rule(:class_workout_missing) == :day
      assert Grouping.rule("inventory_stock_low") == :day
      assert Grouping.rule("a_type_added_later") == :day
    end

    test "messages stack per conversation, follows per day, account security never" do
      assert Grouping.rule(:person_message) == {:conversation, "conversation_id"}
      assert Grouping.rule(:chat_message) == {:conversation, "thread_id"}
      assert Grouping.rule(:new_follower) == :personal_day
      assert Grouping.rule(:workout_changed) == {:subject_day, "scheduled_for"}
      assert Grouping.rule(:password_reset_completed) == :never
    end
  end

  describe "day_zone/2" do
    test "the box's clock for a box's notification, else the recipient's" do
      assert Grouping.day_zone(:day, @box) == :organization
      assert Grouping.day_zone(:day, nil) == :recipient
      assert Grouping.day_zone(:personal_day, @box) == :recipient
      assert Grouping.day_zone({:conversation, "thread_id"}, @box) == :organization
      assert Grouping.day_zone(:never, @box) == :none
    end
  end

  describe "key/4" do
    test "same type, box and day give the same key" do
      key = Grouping.key(:class_workout_missing, %{"class_name" => "A"}, @box, @day)
      assert key == Grouping.key("class_workout_missing", %{"class_name" => "B"}, @box, @day)
      assert key == "class_workout_missing:o:#{@box}:d:2026-11-10"
    end

    test "another day, box or type gives another key" do
      key = Grouping.key(:class_workout_missing, %{}, @box, @day)
      refute key == Grouping.key(:class_workout_missing, %{}, @box, ~D[2026-11-11])
      refute key == Grouping.key(:class_workout_missing, %{}, nil, @day)
      refute key == Grouping.key(:inventory_stock_low, %{}, @box, @day)
    end

    test "a notification without a box keys on '-'" do
      assert Grouping.key(:water_reminder, %{}, nil, @day) == "water_reminder:o:-:d:2026-11-10"
    end

    test "messages key on their conversation, whatever the day" do
      assert Grouping.key(:person_message, %{"conversation_id" => "c1"}, nil, nil) ==
               "person_message:c:c1"

      assert Grouping.key(:buddy_message, %{link_id: "l1"}, @box, @day) == "buddy_message:c:l1"
    end

    test "a message without its conversation falls back to the day" do
      assert Grouping.key(:chat_message, %{}, @box, @day) ==
               "chat_message:o:#{@box}:d:2026-11-10"
    end

    test "follows key on the recipient's day, any box" do
      assert Grouping.key(:new_follower, %{}, @box, @day) == "new_follower:p:d:2026-11-10"
    end

    test "WOD changes key on the WOD's day when it is known" do
      assert Grouping.key(:workout_changed, %{"scheduled_for" => "2026-11-12"}, @box, @day) ==
               "workout_changed:o:#{@box}:d:2026-11-12"

      assert Grouping.key(:workout_changed, %{"scheduled_for" => "soon"}, @box, @day) ==
               "workout_changed:o:#{@box}:d:2026-11-10"
    end

    test "account security never stacks" do
      assert Grouping.key(:password_reset_requested, %{}, nil, @day) == nil
    end
  end

  describe "push_tag/1" do
    test "a short stable tag per key, nil without one" do
      tag = Grouping.push_tag("class_workout_missing:o:#{@box}:d:2026-11-10")
      assert tag == Grouping.push_tag("class_workout_missing:o:#{@box}:d:2026-11-10")
      assert byte_size(tag) <= 64
      assert String.starts_with?(tag, "palee-")
      refute tag == Grouping.push_tag("other")
      assert Grouping.push_tag(nil) == nil
    end
  end
end

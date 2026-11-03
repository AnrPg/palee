defmodule Palee.Notifications.Domain.PushMessageBuilderTest do
  use ExUnit.Case, async: true

  alias Palee.Notifications.Domain.PushMessageBuilder

  test "builds workout note copy with selected text and route" do
    message =
      PushMessageBuilder.build("workout_note", %{
        "execution_id" => "execution-123",
        "note" => %{
          "selected_text" => "Push Press",
          "note_text" => "Felt unstable overhead"
        }
      })

    assert message.title == "Workout annotation"
    assert message.body =~ "Push Press"
    assert message.body =~ "Felt unstable overhead"
    assert message.url == "/workouts/execution-123/execute"
  end

  test "builds booking approval copy with schedule route" do
    message =
      PushMessageBuilder.build("booking_approved", %{
        "class_type_name" => "CrossFit Foundations"
      })

    assert message.title == "Class bookings approved"
    assert message.body =~ "one or more"
    assert message.url == "/box/schedule"
  end

  test "builds consolidated workout assignment copy with athlete route" do
    message = PushMessageBuilder.build("workout_assigned", %{})

    assert message.title == "New workouts assigned"
    assert message.body =~ "one or more"
    assert message.url == "/box/workouts"
  end

  test "builds workout assignment request copy with personal coaching route" do
    message =
      PushMessageBuilder.build("workout_assignment_requested", %{
        "athlete_nickname" => "Atlas",
        "requested_for" => "2026-07-21",
        "note" => "Strength focus"
      })

    assert message.title == "Workout assignment requested"
    assert message.body =~ "Atlas"
    assert message.body =~ "2026-07-21"
    assert message.url == "/admin/coaching-assignments?date=2026-07-21"
  end

  test "builds review submission copy with admin reviews route" do
    message =
      PushMessageBuilder.build("review_submitted", %{
        "rating" => 4,
        "target_type" => "class_slot"
      })

    assert message.title == "New review submitted"
    assert message.body =~ "4/5"
    assert message.url == "/admin/reviews"
  end

  test "scopes admin deep links to the organization the notification belongs to" do
    assert PushMessageBuilder.build("review_submitted", %{
             "rating" => 4,
             "target_type" => "class_slot",
             "organization_slug" => "atlas-gym"
           }).url == "/org/atlas-gym/admin/reviews"

    assert PushMessageBuilder.build("workout_assignment_requested", %{
             "athlete_nickname" => "Atlas",
             "requested_for" => "2026-07-21",
             "organization_slug" => "atlas-gym"
           }).url == "/org/atlas-gym/admin/coaching-assignments?date=2026-07-21"
  end

  test "renders system copy through the supplied locale function while preserving authored text" do
    localize = fn message, bindings ->
      "el:" <>
        Enum.reduce(bindings, message, fn {key, value}, copy ->
          String.replace(copy, "%{#{key}}", to_string(value))
        end)
    end

    message =
      PushMessageBuilder.build(
        "athlete_message",
        %{"sender_nickname" => "Νίκη", "body" => "User-authored body"},
        localize
      )

    assert message.title == "el:Message from Νίκη"
    assert message.body == "User-authored body"
  end

  # ADR-196: fallbacks name pages that exist on the web.
  test "fallback urls open current web routes" do
    assert PushMessageBuilder.build("partner_match", %{}).url == "/messages?filter=partners"
    assert PushMessageBuilder.build("partner_message", %{}).url == "/messages?filter=partners"

    assert PushMessageBuilder.build("journal_export_ready", %{}).url ==
             "/me/settings#journal-export"

    assert PushMessageBuilder.build("package_expiring", %{}).url == "/me/payments"
    assert PushMessageBuilder.build("form_review_completed", %{}).url == "/box/coach"
    assert PushMessageBuilder.build("appointment_cancelled", %{}).url == "/box/appointments"
  end

  # ADR-393: a WOD the person already performed was edited.
  test "builds the WOD-changed notice with its Journal link" do
    message =
      PushMessageBuilder.build("logged_workout_changed", %{
        "workout_title" => "Fran",
        "url" => "/journal?entry=e1"
      })

    assert message.title == "The WOD changed"
    assert message.body == "Fran changed after you did it. See it as it was in your Journal."
    assert message.url == "/journal?entry=e1"

    untitled = PushMessageBuilder.build("logged_workout_changed", %{})
    assert untitled.body == "A WOD you did changed. See it as it was in your Journal."
    assert untitled.url == "/journal"
  end
end

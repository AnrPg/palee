defmodule PaleeWeb.BookingInviteEmailTest do
  @moduledoc """
  ADR-392 «Email κράτησης με ημερολόγιο» through the API, under the
  production runtime role's row-level security like every ConnCase: one
  email per confirmed seat, move and cancellation, with the class's invite
  attached (`METHOD:REQUEST` / `METHOD:CANCEL`, the feed's UID, a growing
  SEQUENCE), only while the person's switch is on.
  """

  use PaleeWeb.ConnCase, async: false

  import Palee.EmailCase
  import Palee.TestFixtures

  alias Palee.{Organizations, Repo}
  alias Palee.Infrastructure.Security.DataCipher

  setup %{conn: conn} do
    {:ok, organization} = Organizations.ensure_legacy_organization_for_migration()
    Repo.query!("SELECT set_config($1, $2, false)", ["app.organization_id", organization.id])
    # ADR-184: a business in demo mode sends no transactional mail.
    activate_business!(organization.id)

    Repo.query!(
      "UPDATE organization_settings SET timezone = 'Europe/Athens', timezone_source = 'confirmed' WHERE organization_id = $1",
      [Ecto.UUID.dump!(organization.id)]
    )

    person = fn role ->
      user = user_fixture()
      {:ok, _} = Organizations.ensure_legacy_membership_for_migration(user, role)
      user
    end

    owner = person.(:owner)
    slug = Organizations.legacy_organization_slug()

    %{
      organization: organization,
      owner: owner,
      member: person.(:member),
      person: person,
      as: fn user -> put_bearer_token(conn, user) end,
      base: "/api/org/#{slug}",
      workout: workout_fixture(owner, %{title: "Fran"})
    }
  end

  defp send_json(conn, method, path, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> dispatch(@endpoint, method, path, Jason.encode!(body))
  end

  defp book(%{as: as, base: base}, user, slot) do
    %{"booking" => booking} =
      as.(user) |> send_json(:post, "#{base}/bookings", %{slot_id: slot.id}) |> json_response(201)

    booking
  end

  # The invite travels in the encrypted body, as the outbox stores it.
  defp invite(message) do
    {:ok, json} = DataCipher.decrypt(message.encrypted_body)
    %{"attachments" => [attachment]} = Jason.decode!(json)
    # RFC 5545 folds long lines; unfolded for the assertions.
    {attachment, attachment["data"] |> Base.decode64!() |> String.replace("\r\n ", "")}
  end

  defp sequence(ics),
    do: ~r/SEQUENCE:(\d+)/ |> Regex.run(ics) |> List.last() |> String.to_integer()

  defp invites(user), do: enqueued_emails(kind: "booking_invite", user_id: user.id)

  test "a confirmed seat gets one email with a REQUEST invite; cancelling it sends a CANCEL",
       ctx do
    %{member: member} = ctx
    slot = slot_fixture(ctx.workout, %{auto_approve: true})
    booking = book(ctx, member, slot)

    message = assert_email_enqueued(kind: "booking_invite", user_id: member.id)
    assert message.to_address == member_email(member)
    assert message.category == "transactional"
    assert message.organization_id == ctx.organization.id
    assert message.subject =~ "Booked: CrossFit"
    # ADR-179: the gym's clock (Athens), not UTC.
    local = slot.scheduled_at |> DateTime.shift_zone!("Europe/Athens")
    assert message.subject =~ Calendar.strftime(local, "%d/%m %H:%M")
    assert message.text =~ "Settings › Notifications"

    {attachment, ics} = invite(message)
    assert attachment["content_type"] == "text/calendar; method=REQUEST; charset=UTF-8"
    assert attachment["filename"] =~ ~r/\.ics$/
    assert ics =~ "METHOD:REQUEST"
    assert ics =~ "UID:class-#{slot.id}@palee"
    assert ics =~ "STATUS:CONFIRMED"
    assert ics =~ "ORGANIZER;CN="

    assert ics =~
             ~r/ATTENDEE;CN="[^"]+";ROLE=REQ-PARTICIPANT;PARTSTAT=ACCEPTED;RSVP=FALSE:mailto:/

    first = sequence(ics)

    # The same UID as «Προσθήκη στο ημερολόγιο».
    download =
      ctx.as.(member)
      |> get("#{ctx.base}/bookings/#{booking["id"]}/calendar.ics")
      |> response(200)

    assert download =~ "UID:class-#{slot.id}@palee"

    Repo.query!("UPDATE bookings SET updated_at = now() + interval '1 minute' WHERE id = $1", [
      Ecto.UUID.dump!(booking["id"])
    ])

    ctx.as.(member) |> delete("#{ctx.base}/bookings/#{booking["id"]}") |> json_response(200)

    cancelled = assert_email_enqueued(kind: "booking_invite", subject: "Cancelled:")
    {attachment, ics} = invite(cancelled)
    assert attachment["content_type"] =~ "method=CANCEL"
    assert ics =~ "METHOD:CANCEL"
    assert ics =~ "STATUS:CANCELLED"
    assert ics =~ "UID:class-#{slot.id}@palee"
    assert sequence(ics) > first
    assert length(invites(member)) == 2
  end

  test "a request waiting for staff gets nothing until it is approved; a withdrawn request nothing",
       ctx do
    %{member: member, owner: owner} = ctx
    slot = slot_fixture(ctx.workout, %{auto_approve: false})
    booking = book(ctx, member, slot)
    refute_email_enqueued(kind: "booking_invite", user_id: member.id)

    ctx.as.(owner)
    |> send_json(:patch, "#{ctx.base}/admin/bookings/#{booking["id"]}/approve", %{})
    |> json_response(200)

    message = assert_email_enqueued(kind: "booking_invite", user_id: member.id)
    {_attachment, ics} = invite(message)
    assert ics =~ "METHOD:REQUEST"

    other = ctx.person.(:member)
    pending = book(ctx, other, slot)
    ctx.as.(other) |> delete("#{ctx.base}/bookings/#{pending["id"]}") |> json_response(200)
    refute_email_enqueued(kind: "booking_invite", user_id: other.id)
  end

  test "the switch in Ρυθμίσεις › Ειδοποιήσεις is on by default and stops the email", ctx do
    %{member: member} = ctx

    preferences =
      ctx.as.(member) |> get("/api/notifications/preferences") |> json_response(200)

    assert %{"channels" => %{"in_app" => true, "push" => true, "email" => true}} =
             Enum.find(preferences["preferences"], &(&1["category"] == "bookings"))

    %{"preferences" => after_change} =
      ctx.as.(member)
      |> send_json(:put, "/api/notifications/preferences/bookings", %{email: false})
      |> json_response(200)

    assert %{"channels" => %{"email" => false, "in_app" => true}} =
             Enum.find(after_change, &(&1["category"] == "bookings"))

    book(ctx, member, slot_fixture(ctx.workout, %{auto_approve: true}))
    refute_email_enqueued(kind: "booking_invite", user_id: member.id)
  end

  test "a class moved to another time sends the updated invite; other edits send nothing", ctx do
    %{member: member, owner: owner} = ctx
    slot = slot_fixture(ctx.workout, %{auto_approve: true})
    book(ctx, member, slot)
    first = assert_email_enqueued(kind: "booking_invite", user_id: member.id)
    {_attachment, first_ics} = invite(first)

    edit = fn changes ->
      body =
        Map.merge(
          %{
            class_type_id: slot.class_type_id,
            scheduled_at: DateTime.to_iso8601(slot.scheduled_at),
            auto_approve: true,
            booking_timeout_minutes: 60,
            capacity: 10
          },
          changes
        )

      ctx.as.(owner)
      |> send_json(:patch, "#{ctx.base}/admin/schedule/slots/#{slot.id}", body)
      |> json_response(200)
    end

    edit.(%{capacity: 12})

    assert length(invites(member)) == 1

    later = DateTime.add(slot.scheduled_at, 2 * 3600, :second)

    edit.(%{scheduled_at: DateTime.to_iso8601(later), capacity: 12})

    changed = assert_email_enqueued(kind: "booking_invite", subject: "Class changed:")
    {_attachment, ics} = invite(changed)
    assert ics =~ "METHOD:REQUEST"
    assert ics =~ "UID:class-#{slot.id}@palee"
    assert ics =~ "DTSTART:#{Calendar.strftime(later, "%Y%m%dT%H%M%SZ")}"
    assert sequence(ics) > sequence(first_ics)
  end

  test "a class the box cancels sends a CANCEL to the people booked, in their language", ctx do
    %{member: member, owner: owner} = ctx

    Repo.query!("UPDATE users SET preferred_locale = 'el' WHERE id = $1", [
      Ecto.UUID.dump!(member.id)
    ])

    slot = slot_fixture(ctx.workout, %{auto_approve: true})
    book(ctx, member, slot)
    booked = assert_email_enqueued(kind: "booking_invite", user_id: member.id)
    assert booked.locale == "el"
    assert booked.subject =~ "Κράτηση: CrossFit"

    ctx.as.(owner)
    |> send_json(:post, "#{ctx.base}/admin/schedule/slots/#{slot.id}/state", %{action: "cancel"})
    |> json_response(200)

    cancelled = assert_email_enqueued(kind: "booking_invite", subject: "Ακυρώθηκε:")
    assert cancelled.text =~ "Ρυθμίσεις › Ειδοποιήσεις"
    {_attachment, ics} = invite(cancelled)
    assert ics =~ "METHOD:CANCEL"
    assert ics =~ "STATUS:CANCELLED"
  end

  defp member_email(member) do
    case Palee.Identity.find_by_id(member.id) do
      %{email: email} -> String.downcase(email)
    end
  end
end

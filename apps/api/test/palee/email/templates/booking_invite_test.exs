defmodule Palee.Email.Templates.BookingInviteTest do
  # ADR-392: «Email κράτησης με ημερολόγιο», in every locale, with the class's
  # day and time on the gym's clock and the way to switch it off.
  use ExUnit.Case, async: true

  alias Palee.Email.Templates
  alias Palee.Email.Templates.BookingInvite

  @locales ~w(ar bg de el en es fr he it nl pt_PT ru)
  # Monday 24 November 2026, 17:00 UTC = 19:00 in Athens.
  @assigns %{
    kind: :booked,
    business: "Alpha <Box>",
    class_name: "CrossFit",
    starts_at: ~U[2026-11-24 17:00:00Z],
    time_zone: "Europe/Athens",
    location: "Alpha, Οδός 1, Αθήνα",
    url: "https://palee.test/box/schedule?open_slot=s1"
  }

  test "is a registered transactional email from the box" do
    assert {:ok, BookingInvite} = Templates.fetch(:booking_invite)
    assert BookingInvite.category() == :transactional
    assert BookingInvite.origin() == :box
  end

  test "English: booked, changed and cancelled, on the gym's clock" do
    assert BookingInvite.subject(@assigns, "en") == "Booked: CrossFit, Tuesday 24/11 19:00"

    assert BookingInvite.subject(%{@assigns | kind: :changed}, "en") ==
             "Class changed: CrossFit, Tuesday 24/11 19:00"

    assert BookingInvite.subject(%{@assigns | kind: :cancelled}, "en") ==
             "Cancelled: CrossFit, Tuesday 24/11 19:00"

    text = BookingInvite.text(@assigns, "en")
    assert text =~ "Your place in CrossFit at «Alpha <Box>» is booked."
    assert text =~ "Alpha, Οδός 1, Αθήνα"
    assert text =~ "adds the class to your calendar"
    assert text =~ "Settings › Notifications"
    assert text =~ @assigns.url

    cancelled = BookingInvite.text(%{@assigns | kind: :cancelled}, "en")
    assert cancelled =~ "removes the class from your calendar"

    html = BookingInvite.html(@assigns, "en")
    # Every value is escaped.
    assert html =~ "Alpha &lt;Box&gt;"
    refute html =~ "Alpha <Box>"
  end

  test "Greek: the weekday in Greek and the settings path as the app names it" do
    assert BookingInvite.subject(@assigns, "el") == "Κράτηση: CrossFit, Τρίτη 24/11 19:00"
    text = BookingInvite.text(%{@assigns | kind: :changed, location: nil}, "el")
    assert text =~ "Το CrossFit στο «Alpha <Box>» άλλαξε. Η θέση σου μένει."
    assert text =~ "Ρυθμίσεις › Ειδοποιήσεις"
    refute text =~ "Πού"
  end

  test "a gym without a known zone says UTC" do
    assert BookingInvite.subject(%{@assigns | time_zone: nil}, "en") =~ "Tuesday 24/11 17:00 UTC"
  end

  test "every locale renders every kind with its own strings" do
    msgids =
      ~w(Monday Tuesday Wednesday Thursday Friday Saturday Sunday) ++
        ["Booked: %{class}, %{when}", "Open in the app"]

    for locale <- @locales, kind <- [:booked, :changed, :cancelled] do
      assigns = %{@assigns | kind: kind}
      assert is_binary(BookingInvite.subject(assigns, locale))
      assert BookingInvite.text(assigns, locale) =~ "CrossFit"
      assert BookingInvite.html(assigns, locale) =~ "CrossFit"
    end

    for dir <- @locales do
      po = File.read!(Path.join(["priv/gettext", dir, "LC_MESSAGES", "emails.po"]))

      for msgid <- msgids do
        assert po =~ ~s(msgid "#{msgid}"\nmsgstr "), "#{dir} lacks #{msgid}"
        refute po =~ ~s(msgid "#{msgid}"\nmsgstr ""\n), "#{dir} leaves #{msgid} untranslated"
      end
    end

    assert BookingInvite.subject(@assigns, "de") =~ "Dienstag"
    assert BookingInvite.subject(@assigns, "he") =~ "יום שלישי"
  end
end

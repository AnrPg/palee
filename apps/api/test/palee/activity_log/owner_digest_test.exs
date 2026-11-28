defmodule Palee.ActivityLog.Domain.OwnerDigestTest do
  # ADR-760 (ANR 12B): the owner's morning summary: the box day it covers,
  # the counts per kind and its words in every locale.
  use ExUnit.Case, async: true

  alias Palee.ActivityLog.Domain.{Actions, OwnerDigest}
  alias Palee.Application.ActivityLogDigest
  alias Palee.Email.Templates
  alias Palee.Email.Templates.ActivityLogDigest, as: Template

  @locales ~w(ar bg de el en es fr he it nl pt_PT ru)

  describe "the box day" do
    test "nothing before 07:00 on the box's clock, yesterday from then on" do
      # 04:59 UTC is 06:59 in Athens (winter), 23:59 the day before in New York.
      assert OwnerDigest.due_day(~U[2026-11-23 04:59:00Z], "Europe/Athens") == :not_yet

      assert OwnerDigest.due_day(~U[2026-11-23 05:00:00Z], "Europe/Athens") ==
               {:ok, ~D[2026-11-22]}

      assert OwnerDigest.due_day(~U[2026-11-23 21:30:00Z], "Europe/Athens") ==
               {:ok, ~D[2026-11-22]}

      # 22:30 UTC is already 00:30 on the 24th in Athens: before its morning.
      assert OwnerDigest.due_day(~U[2026-11-23 22:30:00Z], "Europe/Athens") == :not_yet

      assert OwnerDigest.due_day(~U[2026-11-24 05:00:00Z], "Europe/Athens") ==
               {:ok, ~D[2026-11-23]}

      assert OwnerDigest.due_day(~U[2026-11-23 05:00:00Z], "America/New_York") == :not_yet

      assert OwnerDigest.due_day(~U[2026-11-23 12:00:00Z], "America/New_York") ==
               {:ok, ~D[2026-11-22]}
    end

    test "the window is the box's midnight to midnight, also across a DST change" do
      assert OwnerDigest.window(~D[2026-11-22], "Europe/Athens") ==
               {~U[2026-11-21 22:00:00Z], ~U[2026-11-22 22:00:00Z]}

      # 25 October 2026: Athens goes from UTC+3 to UTC+2 (a 25-hour day).
      assert OwnerDigest.window(~D[2026-10-25], "Europe/Athens") ==
               {~U[2026-10-24 21:00:00Z], ~U[2026-10-25 22:00:00Z]}

      assert OwnerDigest.window(~D[2026-11-22], "America/New_York") ==
               {~U[2026-11-22 05:00:00Z], ~U[2026-11-23 05:00:00Z]}
    end
  end

  describe "counts" do
    test "per kind, most first; only sensitive keys; unnamed ones as other" do
      entries =
        Enum.map(
          ~w(fiscal.credit_note benefit.give fiscal.credit_note payment.record benefit.give fiscal.credit_note),
          &%{action: &1}
        )

      assert OwnerDigest.counts(entries) == [
               %{action: "fiscal.credit_note", count: 3},
               %{action: "benefit.give", count: 2}
             ]

      assert OwnerDigest.total(OwnerDigest.counts(entries)) == 5
      assert OwnerDigest.counts([%{action: "payment.record"}]) == []
    end

    test "every sensitive kind has its words" do
      assert Actions.sensitive_keys() -- Map.keys(OwnerDigest.labels()) == []
      assert Map.keys(OwnerDigest.labels()) -- Actions.sensitive_keys() == []
    end

    test "the link opens the activity log on that day's sensitive rows" do
      assert OwnerDigest.path(~D[2026-11-22]) ==
               "/admin/activity-log?sensitive=1&from=2026-11-22&to=2026-11-22"
    end
  end

  describe "words" do
    test "every locale has every string, translated" do
      pot = File.read!("priv/gettext/activity_log.pot")
      msgids = Regex.scan(~r/^msgid "(.+)"$/m, pot, capture: :all_but_first) |> List.flatten()

      assert Enum.sort(Map.values(OwnerDigest.labels()) ++ ["Other sensitive actions"]) --
               msgids == []

      for dir <- @locales do
        po = File.read!(Path.join(["priv/gettext", dir, "LC_MESSAGES", "activity_log.po"]))
        refute po =~ ~r/milos/i

        for msgid <- msgids do
          assert po =~ ~s(msgid "#{msgid}"\n), "#{dir} lacks #{msgid}"
          refute po =~ ~s(msgid "#{msgid}"\nmsgstr ""\n), "#{dir} leaves #{msgid} untranslated"
        end

        refute po =~ ~r/msgstr\[\d\] ""\n/, "#{dir} leaves a plural form untranslated"
      end
    end

    test "Greek titles and lines, with plurals" do
      assert ActivityLogDigest.title("el", "Box Κυψέλη", 1) ==
               "Box Κυψέλη: 1 ευαίσθητη ενέργεια χθες"

      assert ActivityLogDigest.title("el", "Box Κυψέλη", 4) ==
               "Box Κυψέλη: 4 ευαίσθητες ενέργειες χθες"

      assert ActivityLogDigest.lines("el", [
               %{action: "fiscal.credit_note", count: 2},
               %{action: "other", count: 1}
             ]) == ["Πιστωτικά: 2", "Άλλες ευαίσθητες ενέργειες: 1"]
    end

    test "Russian and Arabic take their own plural forms" do
      assert ActivityLogDigest.title("ru", "Box", 1) =~ "1 важное действие"
      assert ActivityLogDigest.title("ru", "Box", 3) =~ "3 важных действия"
      assert ActivityLogDigest.title("ru", "Box", 5) =~ "5 важных действий"
      assert ActivityLogDigest.title("ar", "Box", 2) =~ "إجراءان"
      assert ActivityLogDigest.title("pt-PT", "Box", 2) =~ "2 ações sensíveis"
    end
  end

  describe "the email" do
    @assigns %{
      box: "Box Κυψέλη",
      date: ~D[2026-11-22],
      total: 3,
      lines: ["Πιστωτικά: 2", "Δώρα σε μέλη box: 1"],
      url:
        "https://palee.test/org/kypseli/admin/activity-log?sensitive=1&from=2026-11-22&to=2026-11-22"
    }

    test "is a registered account email" do
      assert {:ok, Template} = Templates.fetch(:activity_log_digest)
      assert Template.category() == :account
    end

    test "Greek: the counts, the day and the link" do
      assert Template.subject(@assigns, "el") == "Box Κυψέλη: 3 ευαίσθητες ενέργειες χθες"
      text = Template.text(@assigns, "el")
      assert text =~ "22/11/2026"
      assert text =~ "Πιστωτικά: 2"
      assert text =~ "Δώρα σε μέλη box: 1"
      assert text =~ @assigns.url
      assert text =~ "Άνοιξε το Αρχείο ενεργειών"
      assert Template.html(@assigns, "en") =~ "Open the activity log"
    end

    test "renders in every locale" do
      for locale <- ~w(ar bg de el en es fr he it nl pt-PT ru) do
        assert Template.subject(@assigns, locale) =~ "Box Κυψέλη"
        assert Template.html(@assigns, locale) =~ "22/11/2026"
      end
    end
  end
end

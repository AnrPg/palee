defmodule Palee.Email.Templates.ConnectionNoticesTest do
  # ADR-378/379 (2026-11-03): the owners' notices about a new API key and a
  # webhook Palee turned off, in every locale, never carrying a secret.
  use ExUnit.Case, async: true

  alias Palee.Email.Templates
  alias Palee.Email.Templates.{ApiKeyCreated, WebhookDisabled}

  @locales ~w(ar bg de el en es fr he it nl pt_PT ru)
  @key %{
    url: "https://palee.test/org/box/admin/settings?connections=keys#connections",
    box: "Box Κυψέλη",
    name: "Zapier",
    masked: "palee_live_k3m9…",
    scopes: "members:read, classes:read",
    maker: "Μαρία",
    at: "03/11/2026 14:05"
  }
  @hook %{
    url: "https://palee.test/org/box/admin/settings/webhooks/1",
    box: "Box Κυψέλη",
    host: "hooks.zapier.com",
    reason: "too_many_failures"
  }

  test "are registered: the key notice is a security email, the webhook one an account email" do
    assert {:ok, ApiKeyCreated} = Templates.fetch(:api_key_created)
    assert {:ok, WebhookDisabled} = Templates.fetch(:webhook_disabled)
    assert ApiKeyCreated.category() == :security
    assert WebhookDisabled.category() == :account
  end

  test "every locale has every string" do
    msgids =
      Regex.scan(~r/^msgid "(.+)"$/m, File.read!("priv/gettext/integrations.pot"),
        capture: :all_but_first
      )
      |> List.flatten()

    assert length(msgids) == 15

    for dir <- @locales do
      po = File.read!(Path.join(["priv/gettext", dir, "LC_MESSAGES", "integrations.po"]))

      for msgid <- msgids do
        assert po =~ ~s(msgid "#{msgid}"\nmsgstr "), "#{dir} lacks #{msgid}"
        refute po =~ ~s(msgid "#{msgid}"\nmsgstr ""\n), "#{dir} leaves #{msgid} untranslated"
      end
    end
  end

  test "the key notice names the key, who and when, in Greek and English" do
    assert ApiKeyCreated.subject(@key, "el") == "Νέο κλειδί API για το Box Κυψέλη"
    text = ApiKeyCreated.text(@key, "en")
    assert text =~ "Zapier (palee_live_k3m9…)"
    assert text =~ "Made by: Μαρία"
    assert text =~ "03/11/2026 14:05"
    assert text =~ "Settings › Connections"
    assert ApiKeyCreated.html(@key, "el") =~ "Ρυθμίσεις › Συνδέσεις"
  end

  test "the webhook notice says why and what to do" do
    assert WebhookDisabled.subject(@hook, "en") == "A webhook of Box Κυψέλη was turned off"
    assert WebhookDisabled.text(@hook, "en") =~ "many times in a row"
    assert WebhookDisabled.text(%{@hook | reason: "gone"}, "el") =~ "δεν υπάρχει πια"
    assert WebhookDisabled.html(@hook, "de") =~ "hooks.zapier.com"
  end
end

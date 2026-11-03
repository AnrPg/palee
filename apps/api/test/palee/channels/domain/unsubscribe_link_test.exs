defmodule Palee.Channels.Domain.UnsubscribeLinkTest do
  use ExUnit.Case, async: true

  alias Palee.Channels.Domain.{Templates, UnsubscribeLink}

  @key UnsubscribeLink.derive_key("test-key")
  @contact "0b9f6c7e-2a51-4b8e-9d3c-5f1a2b3c4d5e"

  test "a short signed token that names the contact" do
    token = UnsubscribeLink.sign(@key, @contact)
    assert String.length(token) == 30
    assert token =~ ~r/^[A-Za-z0-9_-]+$/
    assert {:ok, @contact} = UnsubscribeLink.verify(@key, token)
  end

  test "another key, a changed token or junk is refused" do
    token = UnsubscribeLink.sign(@key, @contact)
    assert :error = UnsubscribeLink.verify(UnsubscribeLink.derive_key("other"), token)
    <<first, rest::binary>> = token
    assert :error = UnsubscribeLink.verify(@key, <<if(first == ?A, do: ?B, else: ?A)>> <> rest)
    # Only the one spelling of the token counts.
    last = String.last(token)
    other = if last == "A", do: "B", else: "A"
    assert :error = UnsubscribeLink.verify(@key, String.slice(token, 0, 29) <> other)
    assert :error = UnsubscribeLink.verify(@key, "")
    assert :error = UnsubscribeLink.verify(@key, String.duplicate("A", 65))
    assert :error = UnsubscribeLink.verify(@key, nil)
  end

  test "the link on the app host without the scheme, and the word per language" do
    assert UnsubscribeLink.url("https://palee.app/", "abc") == "palee.app/u/abc"
    assert UnsubscribeLink.url("http://localhost:4000", "abc") == "http://localhost:4000/u/abc"
    assert Templates.opt_out("el", "palee.app/u/abc") == " Διακοπή: palee.app/u/abc"
    assert Templates.opt_out("de", "x") == " Abmelden: x"
    assert Templates.opt_out("xx", "x") == " Stop: x"
  end
end

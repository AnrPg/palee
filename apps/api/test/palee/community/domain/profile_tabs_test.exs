defmodule Palee.Community.Domain.ProfileTabsTest do
  @moduledoc "ADR-554: the tabs of a profile and its «Λίγα λόγια»."

  use ExUnit.Case, async: true

  alias Palee.Community.Domain.ProfileTabs

  test "fixed tabs always come first, then the stored optional ones in order" do
    assert ProfileTabs.shown([]) == ["media", "posts"]
    assert ProfileTabs.shown(nil) == ["media", "posts"]
    assert ProfileTabs.shown(["badges", "prs"]) == ["media", "posts", "badges", "prs"]
  end

  test "normalize keeps known optional tabs once, in the order given" do
    assert ProfileTabs.normalize(["prs", "media", "unknown", "badges", "prs"]) == [
             "prs",
             "badges"
           ]

    assert ProfileTabs.normalize("prs") == []
    assert ProfileTabs.normalize(nil) == []
  end

  test "bio is trimmed and blank counts as none" do
    assert ProfileTabs.bio("  Crossfit και καφές  ") == "Crossfit και καφές"
    assert ProfileTabs.bio("   ") == nil
    assert ProfileTabs.bio("") == nil
    assert ProfileTabs.bio(nil) == nil
    assert ProfileTabs.bio(42) == nil
  end
end

defmodule Palee.BoxData.Domain.FilePackingTest do
  @moduledoc "ADR-367: which stored files go into the box's export and how they are split."

  use ExUnit.Case, async: true

  alias Palee.BoxData.Domain.FilePacking

  @prefix "organizations/org-1/"

  defp object(source, key, size, bucket \\ :documents),
    do: %{source: source, bucket: bucket, key: @prefix <> key, size: size}

  test "everything under the box's prefix goes in, by kind, never earlier exports" do
    selected =
      FilePacking.select(
        [
          object(:documents, "documents/contract.pdf", 10),
          object(:branding, "branding/logo.png", 5, :branding),
          object(:media, "media/p1/photo.jpg", 20, :media_public),
          object(:media, "posts/p2/clip.mp4", 30, :media_public),
          object(:documents, "exports/box-data/e1/palee.zip", 99),
          object(:documents, "folder/", 0),
          object(:documents, "a/../../other-org/secret.pdf", 1),
          %{source: :documents, bucket: :documents, key: "organizations/org-2/x.pdf", size: 1}
        ],
        @prefix
      )

    assert Enum.map(selected, & &1.entry) == [
             "branding/logo.png",
             "documents/contract.pdf",
             "media/p1/photo.jpg",
             "media/posts/p2/clip.mp4"
           ]
  end

  test "parts stay under the limit; a big file gets its own part; no files, no parts" do
    objects = [
      %{entry: "a", size: 40},
      %{entry: "b", size: 50},
      %{entry: "c", size: 30},
      %{entry: "d", size: 250},
      %{entry: "e", size: 10}
    ]

    assert FilePacking.plan(objects, 100) |> Enum.map(fn part -> Enum.map(part, & &1.entry) end) ==
             [["a", "b"], ["c"], ["d"], ["e"]]

    assert FilePacking.plan([], 100) == []
  end
end

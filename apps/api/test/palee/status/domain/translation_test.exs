defmodule Palee.Status.Domain.TranslationTest do
  @moduledoc "ADR-366: the English copy of an incident and who reads what."

  use ExUnit.Case, async: true

  alias Palee.Status.Domain.Translation

  describe "from_params/2" do
    test "keeps the source language and the English copy of a new incident" do
      assert {:ok,
              %{
                locale: "el",
                title_en: "Email delays",
                body_en: "Receipts are late.",
                en_source: "auto"
              }} =
               Translation.from_params(
                 %{"locale" => "EL", "title_en" => " Email delays ", "body_en" => "Receipts are late."},
                 :incident
               )
    end

    test "an edited copy says so; a step carries only its note" do
      assert {:ok, %{title_en: nil, body_en: "Fixed.", en_source: "edited"}} =
               Translation.from_params(
                 %{locale: "de", body_en: "Fixed.", en_source: "edited", title_en: "ignored"},
                 :update
               )
    end

    test "English text and missing translations carry no copy" do
      assert {:ok, %{locale: "en-gb", title_en: nil, body_en: nil, en_source: nil}} =
               Translation.from_params(%{locale: "en-GB", title_en: "x y z", body_en: "b"}, :incident)

      assert {:ok, %{locale: "el", body_en: nil, en_source: nil}} =
               Translation.from_params(%{locale: "el"}, :incident)

      assert {:ok, %{locale: nil}} = Translation.from_params(%{locale: "not a tag!"}, :update)
    end

    test "a half or too long copy is refused" do
      assert {:error, :invalid_status_translation} =
               Translation.from_params(%{locale: "el", title_en: "Email delays"}, :incident)

      assert {:error, :invalid_status_translation} =
               Translation.from_params(
                 %{locale: "el", title_en: "ab", body_en: "Receipts are late."},
                 :incident
               )

      assert {:error, :invalid_status_translation} =
               Translation.from_params(
                 %{locale: "el", body_en: String.duplicate("a", 2001)},
                 :update
               )
    end
  end

  describe "request/1 and result/1" do
    test "a note is needed; the title is optional" do
      assert {:ok, %{title: nil, body: "Hi"}} = Translation.request(%{"body" => " Hi "})
      assert {:error, :invalid_status_note} = Translation.request(%{"title" => "Title"})
      assert {:error, :invalid_status_title} = Translation.request(%{title: "ab", body: "x"})
    end

    test "an answer is trimmed and clipped; an empty one is unavailable" do
      assert {:ok, %{locale: "el", title: "Email delays", body: "Late."}} =
               Translation.result(%{locale: "el", title: " Email delays ", body: " Late. "})

      assert {:ok, %{title: title}} =
               Translation.result(%{locale: "el", title: String.duplicate("a", 200), body: "x"})

      assert String.length(title) == 140

      assert {:error, :status_translation_unavailable} =
               Translation.result(%{locale: "el", title: nil, body: "  "})

      assert {:error, :status_translation_unavailable} = Translation.result(:nope)
    end
  end

  describe "for_reader/3" do
    @incident %{title: "Καθυστερήσεις", title_en: "Delays", locale: "el", en_source: "auto"}
    @update %{body: "Το ερευνούμε.", body_en: "We are looking into it.", locale: "el", en_source: "auto"}

    test "a reader of the source language reads the original" do
      assert %{title: "Καθυστερήσεις", body: "Το ερευνούμε.", machine: false} =
               Translation.for_reader(@incident, @update, "el")
    end

    test "everyone else reads the English copy, marked as a machine translation" do
      assert %{title: "Delays", body: "We are looking into it.", machine: true} =
               Translation.for_reader(@incident, @update, "de")

      assert %{machine: false} =
               Translation.for_reader(@incident, %{@update | en_source: "edited"}, "fr")
    end

    test "without an English copy everyone reads the original" do
      incident = %{@incident | title_en: nil, en_source: nil}
      update = %{@update | body_en: nil, en_source: nil}

      assert %{title: "Καθυστερήσεις", body: "Το ερευνούμε.", machine: false} =
               Translation.for_reader(incident, update, "en")
    end
  end
end

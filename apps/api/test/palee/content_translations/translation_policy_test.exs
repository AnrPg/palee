defmodule Palee.ContentTranslations.TranslationPolicyTest do
  use ExUnit.Case, async: true

  alias Palee.ContentTranslations.Domain.{Subjects, TranslationPolicy}

  @id "6d6b6a0e-5d7f-4c4e-9a43-0d8b5c1f2a10"

  test "the languages are the app's languages" do
    assert Enum.sort(TranslationPolicy.locales()) ==
             Enum.sort(Palee.Identity.Domain.Locale.supported())
  end

  test "locales are canonical and the box's own language is left out" do
    assert {:ok, "pt-PT"} = TranslationPolicy.locale(" PT_pt ")
    assert {:error, :unsupported_locale} = TranslationPolicy.locale("xx")
    assert {:error, :unsupported_locale} = TranslationPolicy.locale(nil)

    assert {:ok, %{translation_locales: ["en", "de"], visible_locales: ["en"]}} =
             TranslationPolicy.languages(["en", "EL", "de", "en"], ["en", "fr"], "el")

    assert {:error, :translation_locales} = TranslationPolicy.languages(["zz"], [], "el")
    assert {:error, :visible_locales} = TranslationPolicy.languages(["en"], "en", "el")
  end

  test "status follows the source the translation was made from" do
    source = "Απεριόριστο μηνιαίο"
    hash = TranslationPolicy.source_hash(source)
    assert hash =~ ~r/^[0-9a-f]{64}$/

    assert TranslationPolicy.status(source, nil) == :missing

    assert TranslationPolicy.status(source, %{
             source_hash: hash,
             origin: "manual",
             reviewed_at: ~U[2026-11-04 00:00:00Z]
           }) ==
             :ok

    assert TranslationPolicy.status(source, %{
             source_hash: hash,
             origin: "machine",
             reviewed_at: nil
           }) ==
             :machine

    assert TranslationPolicy.status("Άλλο", %{
             source_hash: hash,
             origin: "manual",
             reviewed_at: ~U[2026-11-04 00:00:00Z]
           }) ==
             :stale

    assert TranslationPolicy.machine_may_write?(:missing)
    assert TranslationPolicy.machine_may_write?(:stale)
    refute TranslationPolicy.machine_may_write?(:ok)
    refute TranslationPolicy.machine_may_write?(:machine)

    assert TranslationPolicy.counts([:ok, :ok, :missing]) == %{
             ok: 2,
             missing: 1,
             stale: 0,
             machine: 0
           }
  end

  test "a person's edit is checked against the catalog" do
    assert {:ok, {:put, {"package", @id, "name"}, "Unlimited"}} =
             TranslationPolicy.edit(%{
               kind: "package",
               id: @id,
               field: "name",
               text: " Unlimited "
             })

    assert {:ok, {:delete, {"package", @id, "name"}}} =
             TranslationPolicy.edit(%{
               "kind" => "package",
               "id" => @id,
               "field" => "name",
               "text" => "  "
             })

    assert {:error, {:invalid_fields, %{field: _}}} =
             TranslationPolicy.edit(%{kind: "package", id: @id, field: "price", text: "x"})

    assert {:error, {:invalid_fields, %{id: _}}} =
             TranslationPolicy.edit(%{kind: "package", id: "1", field: "name", text: "x"})

    long = String.duplicate("a", Subjects.max_length("class_type", "name") + 1)

    assert {:error, {:invalid_fields, %{text: "too_long"}}} =
             TranslationPolicy.edit(%{kind: "class_type", id: @id, field: "name", text: long})
  end

  test "keys round-trip and machine text is trimmed to the field" do
    key = {"site_faq", @id, "answer"}
    assert {:ok, ^key} = key |> TranslationPolicy.key_string() |> TranslationPolicy.parse_key()
    assert {:error, _} = TranslationPolicy.parse_key("site_faq:#{@id}:price")

    assert TranslationPolicy.machine_text({"class_type", @id, "name"}, "  ") == nil

    assert String.length(
             TranslationPolicy.machine_text(
               {"class_type", @id, "name"},
               String.duplicate("b", 500)
             )
           ) ==
             120

    row = TranslationPolicy.machine_row(key, "Yes", "Ναι")
    assert row.origin == "machine" and is_nil(row.reviewed_at)
    row = TranslationPolicy.manual_row(key, "Yes", "Ναι", ~U[2026-11-04 00:00:00Z], nil)
    assert row.origin == "manual" and row.reviewed_at == ~U[2026-11-04 00:00:00Z]
  end
end

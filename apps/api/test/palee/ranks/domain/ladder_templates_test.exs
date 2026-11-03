defmodule Palee.Ranks.Domain.LadderTemplatesTest do
  @moduledoc """
  ADR-400: the template catalogue. Every template is a valid ladder in every
  language, keeps the keys clients already send, and every text has its
  Greek translation in the `rank_templates` catalogue.
  """

  use ExUnit.Case, async: true

  alias Palee.Localization
  alias Palee.Ranks.Domain.LadderPolicy
  alias Palee.Workouts.Domain.WorkoutType

  @locales ~w(en el ar ru de es pt-PT he it bg nl fr)

  defp localized(locale) do
    Enum.map(
      LadderPolicy.templates(),
      &LadderPolicy.localize_template(&1, fn message, bindings ->
        Localization.translate(locale, message, bindings, "rank_templates")
      end)
    )
  end

  test "keeps the three original templates and gives each key once" do
    keys = Enum.map(LadderPolicy.templates(), & &1.key)
    assert keys == Enum.uniq(keys)
    assert ~w(bjj_adult karate_kyu gymnastics_levels) -- keys == []
    assert length(keys) >= 70
  end

  test "every template is a valid ladder in every language" do
    for locale <- @locales, template <- localized(locale) do
      assert WorkoutType.valid?(template.discipline), template.key
      assert template.family == WorkoutType.family(template.discipline)
      assert template.style in LadderPolicy.styles()
      assert template.source in ~w(federation palee)
      assert is_binary(template.name) and template.name != ""

      assert {:ok, _ranks} = LadderPolicy.cast_ranks(template.ranks, []),
             "#{locale} #{template.key}"

      # The web editor splits skills on commas.
      for rank <- template.ranks, skill <- Map.get(rank.requirements, :skills, []) do
        refute String.contains?(skill, ","), "#{locale} #{template.key}: #{skill}"
      end
    end
  end

  test "Greek has every name and skill; other languages have every template name" do
    greek = catalogue("el")

    for template <- LadderPolicy.templates() do
      assert Map.get(greek, template.name, "") != "", "no Greek for #{template.name}"

      for rank <- template.ranks, skill <- Map.get(rank.requirements, :skills, []) do
        assert Map.get(greek, skill, "") != "", "#{template.key}: no Greek for #{skill}"
      end

      for locale <- ~w(ar ru de es pt_PT he it bg nl fr) do
        assert Map.get(catalogue(locale), template.name, "") != "", "#{locale}: #{template.key}"
      end
    end
  end

  defp catalogue(locale) do
    "priv/gettext/#{locale}/LC_MESSAGES/rank_templates.po"
    |> File.read!()
    |> then(&Regex.scan(~r/^msgid "((?:[^"\\]|\\.)*)"\nmsgstr "((?:[^"\\]|\\.)*)"$/m, &1))
    |> Map.new(fn [_line, id, text] -> {unescape(id), unescape(text)} end)
  end

  defp unescape(text), do: String.replace(text, ~S(\"), ~S("))

  test "the original templates read as before in Greek" do
    bjj = Enum.find(localized("el"), &(&1.key == "bjj_adult"))
    assert bjj.name == "Ζώνες BJJ"
    assert Enum.map(bjj.ranks, & &1.name) == ~w(Λευκή Μπλε Μωβ Καφέ Μαύρη)
    # IBJJF minimum time: 2 years as blue, 18 months as purple, 1 year as brown.
    assert Enum.map(bjj.ranks, &Map.get(&1.requirements, :min_days)) == [nil, nil, 730, 540, 365]

    levels = Enum.find(localized("el"), &(&1.key == "gymnastics_levels"))
    assert hd(levels.ranks).name == "Επίπεδο 1"
    assert List.last(levels.ranks).name == "Επίπεδο 10"

    assert Enum.find(localized("en"), &(&1.key == "karate_kyu")).ranks |> hd() |> Map.get(:name) ==
             "White"
  end
end

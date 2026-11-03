defmodule Palee.Ranks.Domain.RanksDomainTest do
  @moduledoc "ADR-377: ladders, promotions and diplomas."

  use ExUnit.Case, async: true

  alias Palee.Ranks.Domain.{CertificatePdf, LadderPolicy, PromotionPolicy}

  describe "LadderPolicy" do
    test "disciplines are the workout types of ADR-275" do
      assert "bjj_grappling" in LadderPolicy.disciplines()
      assert LadderPolicy.family("bjj_grappling") == "combat"
      assert LadderPolicy.family("gymnastics") == "gymnastics"
    end

    test "casts ranks in order with requirements and the box's scale levels" do
      assert {:ok, [white, blue]} =
               LadderPolicy.cast_ranks(
                 [
                   %{"name" => " Λευκή ", "color" => "white", "max_stripes" => 4},
                   %{
                     name: "Μπλε",
                     color: "blue",
                     scale_level_slug: "rx",
                     requirements: %{
                       min_classes: 100,
                       min_days: 730,
                       skills: ["Armbar ", "Triangle"]
                     }
                   }
                 ],
                 ["scaled", "rx"]
               )

      assert %{position: 0, name: "Λευκή", max_stripes: 4, requirements: %{}} = white

      assert %{
               position: 1,
               requirements: %{"min_classes" => 100, "skills" => ["Armbar", "Triangle"]}
             } =
               blue
    end

    test "refuses bad ladders" do
      for ranks <- [
            [],
            [%{name: ""}],
            [%{name: "A", color: "teal"}],
            [%{name: "A", max_stripes: 11}],
            [%{name: "A", scale_level_slug: "elite"}],
            [%{name: "A"}, %{name: "a"}],
            [%{name: "A", requirements: %{min_days: -1}}],
            [%{name: "A", id: "not-a-uuid"}]
          ] do
        assert {:error, {:invalid_ranks, _message}} = LadderPolicy.cast_ranks(ranks, ["rx"])
      end
    end

    test "every template is a valid ladder" do
      for template <- LadderPolicy.templates() do
        assert template.discipline in LadderPolicy.disciplines()
        assert {:ok, _ranks} = LadderPolicy.cast_ranks(template.ranks, [])
      end
    end
  end

  describe "PromotionPolicy" do
    @today ~D[2026-10-31]

    test "the current award ignores withdrawn ones" do
      older = award("a", ~D[2025-01-01])
      newer = award("b", ~D[2026-01-01])
      revoked = %{award("c", ~D[2026-06-01]) | revoked_at: ~U[2026-06-02 00:00:00Z]}
      assert PromotionPolicy.current([older, revoked, newer]).id == "b"
      assert PromotionPolicy.current([]) == nil
    end

    test "progress counts classes and days towards the next rank" do
      ranks = [
        rank(0, %{}),
        rank(1, %{"min_classes" => 3, "min_days" => 100, "skills" => ["Armbar"]})
      ]

      assert PromotionPolicy.next_rank(ranks, nil).position == 0
      assert PromotionPolicy.next_rank(ranks, hd(ranks)).position == 1
      assert PromotionPolicy.next_rank(ranks, List.last(ranks)) == nil

      history = [
        %{
          attendance_status: "attended",
          class_type_id: "bjj",
          scheduled_at: ~U[2026-09-01 18:00:00Z]
        },
        %{
          attendance_status: "attended",
          class_type_id: "bjj",
          scheduled_at: ~U[2026-01-01 18:00:00Z]
        },
        %{
          attendance_status: "missed",
          class_type_id: "bjj",
          scheduled_at: ~U[2026-09-02 18:00:00Z]
        },
        %{
          attendance_status: "attended",
          class_type_id: "yoga",
          scheduled_at: ~U[2026-09-03 18:00:00Z]
        }
      ]

      assert PromotionPolicy.count_attended(history, ["bjj"], ~D[2026-06-01]) == 1
      assert PromotionPolicy.count_attended(history, [], nil) == 3

      progress = PromotionPolicy.progress(List.last(ranks), ~D[2026-06-01], 3, @today)
      assert progress.classes == %{done: 3, needed: 3}
      assert progress.days == %{done: 152, needed: 100}
      assert progress.skills == ["Armbar"]
      assert progress.ready
      refute PromotionPolicy.progress(List.last(ranks), ~D[2026-10-01], 3, @today).ready
      assert PromotionPolicy.progress(nil, nil, 0, @today) == nil
    end

    test "an award goes up or adds stripes, never down" do
      white = Map.put(rank(0, %{}), :max_stripes, 4)
      blue = Map.put(rank(1, %{"skills" => ["Armbar"]}), :max_stripes, 4)

      assert :ok = PromotionPolicy.validate_award(white, 0, [], nil, 0, @today, @today)
      assert :ok = PromotionPolicy.validate_award(white, 2, [], white, 1, @today, @today)
      assert :ok = PromotionPolicy.validate_award(blue, 0, ["Armbar"], white, 4, @today, @today)

      assert {:error, :rank_not_above_current} =
               PromotionPolicy.validate_award(white, 1, [], white, 1, @today, @today)

      assert {:error, :rank_not_above_current} =
               PromotionPolicy.validate_award(white, 0, [], blue, 0, @today, @today)

      assert {:error, :too_many_stripes} =
               PromotionPolicy.validate_award(white, 5, [], nil, 0, @today, @today)

      assert {:error, :award_in_future} =
               PromotionPolicy.validate_award(white, 0, [], nil, 0, ~D[2026-11-01], @today)

      assert {:error, :unknown_skills} =
               PromotionPolicy.validate_award(blue, 0, ["Kimura"], nil, 0, @today, @today)
    end

    test "diploma numbers" do
      assert PromotionPolicy.certificate_number("3f9a1c2b-0000-0000-0000-000000000000", @today) ==
               "R-2026-3F9A1C2B"
    end
  end

  test "the diploma names the box, the person, the rank and the number" do
    view = %{
      box: "Dojo Αθήνα",
      person: "Μαρία",
      ladder: "Ζώνες BJJ",
      rank: "Μπλε",
      color: "blue",
      stripes: 2,
      awarded_on: ~D[2026-10-31],
      awarded_by: "Νίκος",
      number: "R-2026-3F9A1C2B",
      revoked: false
    }

    fonts = Palee.Pdf.Fonts.sans()
    texts = view |> CertificatePdf.texts(fonts) |> Enum.map(&elem_text/1) |> Enum.join("\n")

    for text <- [
          "Dojo Αθήνα",
          "ΔΙΠΛΩΜΑ",
          "Μαρία",
          "Μπλε · 2 ρίγες",
          "31/10/2026",
          "Νίκος · Coach",
          "R-2026-3F9A1C2B"
        ] do
      assert texts =~ text
    end

    refute texts =~ "Ανακλήθηκε"

    assert view
           |> Map.put(:revoked, true)
           |> CertificatePdf.texts(fonts)
           |> Enum.map(&elem_text/1)
           |> Enum.member?("Ανακλήθηκε")

    assert "%PDF" <> _rest = CertificatePdf.render(view, fonts)
  end

  defp elem_text(%{text: text}), do: text
  defp elem_text({_x, _y, text}), do: text
  defp elem_text(text) when is_binary(text), do: text

  defp award(id, on),
    do: %{id: id, awarded_on: on, inserted_at: ~U[2026-01-01 00:00:00Z], revoked_at: nil}

  defp rank(position, requirements),
    do: %{id: "r#{position}", position: position, requirements: requirements, max_stripes: 0}
end

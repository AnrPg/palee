defmodule Palee.Ranks.Domain.RanksDomainTest do
  @moduledoc "ADR-377: ladders, promotions and diplomas."

  use ExUnit.Case, async: true

  alias Palee.Ranks.Domain.{CertificatePdf, LadderPolicy, PromotionPolicy, SkillNoticePolicy}

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

    test "skills keep stable ids through renames, new orders and old clients" do
      a = "00000000-0000-0000-0000-00000000000a"
      b = "00000000-0000-0000-0000-00000000000b"

      existing = [
        %{id: "r1", requirements: %{"skills" => ["Armbar", "Triangle"], "skill_ids" => [a, b]}}
      ]

      counter = :counters.new(1, [])

      new_id = fn ->
        :counters.add(counter, 1, 1)
        "new-#{:counters.get(counter, 1)}"
      end

      # Reordered and renamed by id; a new skill gets a new id.
      {:ok, [rank]} =
        LadderPolicy.cast_ranks(
          [
            %{
              name: "Blue",
              requirements: %{
                skills: ["Triangle choke", "Armbar", "Kimura"],
                skill_ids: [b, a, nil]
              }
            }
          ],
          []
        )

      assert [%{requirements: %{"skill_ids" => [^b, ^a, "new-1"]}}] =
               LadderPolicy.assign_skill_ids([Map.put(rank, :id, "r1")], existing, new_id)

      # An old client sends the texts only: a known text keeps its id.
      {:ok, [old]} =
        LadderPolicy.cast_ranks(
          [%{name: "Blue", requirements: %{skills: ["Triangle", "Armbar"]}}],
          []
        )

      assert [%{requirements: %{"skill_ids" => [^b, ^a]}}] =
               LadderPolicy.assign_skill_ids([Map.put(old, :id, "r1")], existing, new_id)

      # An id sent twice is used once.
      {:ok, [twice]} =
        LadderPolicy.cast_ranks(
          [%{name: "Blue", requirements: %{skills: ["X", "Y"], skill_ids: [a, a]}}],
          []
        )

      assert [%{requirements: %{"skill_ids" => [^a, second]}}] =
               LadderPolicy.assign_skill_ids([Map.put(twice, :id, "r1")], existing, new_id)

      refute second == a

      assert {:ok, {^b, "Triangle"}} = LadderPolicy.find_skill(hd(existing), b, nil)
      assert {:ok, {^a, "Armbar"}} = LadderPolicy.find_skill(hd(existing), nil, "Armbar")
      assert :error = LadderPolicy.find_skill(hd(existing), nil, "Kimura")

      for bad <- [
            %{skills: ["X"], skill_ids: ["nope"]},
            %{skills: ["X"], skill_ids: [a, b]},
            %{skills: ["X"], skill_notes: [String.duplicate("n", 501)]},
            %{skills: ["X"], skill_videos: ["http://example.com/v"]}
          ] do
        assert {:error, _message} = LadderPolicy.cast_requirements(bad)
      end
    end

    test "a skill may carry a note and a video link; none leaves them out" do
      assert {:ok,
              %{
                "skill_notes" => [nil, "Both sides"],
                "skill_videos" => ["https://v.example/1", nil]
              }} =
               LadderPolicy.cast_requirements(%{
                 skills: ["A", "B"],
                 skill_notes: ["", " Both sides "],
                 skill_videos: ["https://v.example/1", nil]
               })

      assert {:ok, requirements} =
               LadderPolicy.cast_requirements(%{
                 skills: ["A"],
                 skill_notes: [nil],
                 skill_videos: [""]
               })

      refute Map.has_key?(requirements, "skill_notes")
      refute Map.has_key?(requirements, "skill_videos")
    end

    test "what counts for ready is a non-empty choice of days, classes and skills" do
      assert {:ok, ["days", "skills"]} = LadderPolicy.cast_ready_criteria(["skills", "days"], [])
      assert {:ok, ["classes"]} = LadderPolicy.cast_ready_criteria(nil, ["classes"])
      assert {:error, _} = LadderPolicy.cast_ready_criteria([], [])
      assert {:error, _} = LadderPolicy.cast_ready_criteria(["belts"], [])
    end

    test "templates count what their system states" do
      bjj = LadderPolicy.template("bjj_adult")
      assert bjj.ready == ["days", "skills"]
      assert LadderPolicy.template("trampoline_awards").ready == ["skills"]
      assert LadderPolicy.template("gymnastics_levels").ready == ["skills"]
      assert LadderPolicy.template("reggaeton_levels").discipline == "latin_dance"
    end

    # Every template as a valid ladder in every language: LadderTemplatesTest.
    test "every template names a known discipline" do
      for template <- LadderPolicy.templates() do
        assert template.discipline in LadderPolicy.disciplines()
      end
    end

    test "a template reads in one language, numbered names with their number" do
      template = %{
        key: "x",
        name: "Levels",
        discipline: "judo",
        style: "level",
        ranks: [%{name: {"Level %{n}", 2}, requirements: %{skills: ["Roll"]}}]
      }

      translate = fn message, bindings ->
        "el:" <> String.replace(message, "%{n}", to_string(Map.get(bindings, :n, "")))
      end

      assert %{
               name: "el:Levels",
               family: "combat",
               ranks: [%{name: "el:Level 2", requirements: %{skills: ["el:Roll"]}}]
             } = LadderPolicy.localize_template(template, translate)
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
      assert progress.skills_checked == []
      refute progress.all_skills_checked
      assert progress.ready

      # ADR-400: skills ticked one by one count only for that rank and its list.
      checks = [
        %{rank_id: "r1", skill: "Armbar", checked_on: ~D[2026-09-01], note: nil},
        %{rank_id: "r1", skill: "Renamed away", checked_on: ~D[2026-09-01], note: nil},
        %{rank_id: "r0", skill: "Armbar", checked_on: ~D[2026-09-01], note: nil}
      ]

      ticked = PromotionPolicy.progress(List.last(ranks), ~D[2026-06-01], 3, @today, checks)
      assert [%{skill: "Armbar", checked_on: ~D[2026-09-01]}] = ticked.skills_checked
      assert ticked.all_skills_checked
      assert PromotionPolicy.progress(hd(ranks), nil, 0, @today).all_skills_checked
      refute PromotionPolicy.progress(List.last(ranks), ~D[2026-10-01], 3, @today).ready
      assert PromotionPolicy.progress(nil, nil, 0, @today) == nil
    end

    test "ticks follow the skill's id, and ready counts only the ladder's criteria" do
      next = %{
        id: "r1",
        position: 1,
        requirements: %{
          "min_days" => 100,
          "skills" => ["Armbar choke", "Triangle"],
          "skill_ids" => ["s-a", "s-t"]
        }
      }

      # Ticked as «Armbar», renamed since: still ticked, with today's text.
      checks = [
        %{rank_id: "r1", skill_id: "s-a", skill: "Armbar", checked_on: @today, note: "ok"}
      ]

      days_only = PromotionPolicy.progress(next, ~D[2026-01-01], 0, @today, checks, ["days"])
      assert [%{skill: "Armbar choke", skill_id: "s-a", note: "ok"}] = days_only.skills_checked
      assert days_only.skill_ids == ["s-a", "s-t"]
      assert days_only.ready
      refute days_only.all_skills_checked

      refute PromotionPolicy.progress(next, ~D[2026-01-01], 0, @today, checks, ["skills"]).ready

      refute PromotionPolicy.progress(next, ~D[2026-01-01], 0, @today, checks, ["days", "skills"]).ready

      all =
        checks ++
          [%{rank_id: "r1", skill_id: "s-t", skill: "Triangle", checked_on: @today, note: nil}]

      assert PromotionPolicy.progress(next, ~D[2026-01-01], 0, @today, all, ["days", "skills"]).ready

      # Days not reached: a ladder counting them is not ready.
      refute PromotionPolicy.progress(next, ~D[2026-10-01], 0, @today, all, ["days", "skills"]).ready
      assert PromotionPolicy.progress(next, ~D[2026-10-01], 0, @today, all, ["skills"]).ready
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

    # The line names the awarder's role in that box.
    assert view
           |> Map.put(:awarded_by_role, "Ιδιοκτήτης")
           |> CertificatePdf.texts(fonts)
           |> Enum.map(&elem_text/1)
           |> Enum.member?("Νίκος · Ιδιοκτήτης")
  end

  test "the diploma's role names follow the ontology" do
    assert CertificatePdf.role_label([:coach], :all) == "Head coach"
    assert CertificatePdf.role_label([:member, :coach], :own) == "Coach"
    assert CertificatePdf.role_label([:owner, :coach], :own) == "Coach"
    assert CertificatePdf.role_label([:owner], :own) == "Ιδιοκτήτης"
    assert CertificatePdf.role_label([:admin], :own) == "Διαχειριστής"
    assert CertificatePdf.role_label([:front_desk], :own) == "Coach"
    assert CertificatePdf.role_label(nil, nil) == "Coach"
  end

  describe "SkillNoticePolicy" do
    test "groups the ticks into one notice and is silent when every tick was undone" do
      ranks = %{"blue" => %{name: "Μπλε", position: 1}, "purple" => %{name: "Μωβ", position: 2}}
      tick = fn rank_id -> %{rank_id: rank_id} end

      assert %{count: 3, rank_id: "blue", rank_name: "Μπλε", ranks: 2} =
               SkillNoticePolicy.notice([tick.("blue"), tick.("purple"), tick.("blue")], ranks)

      # A tie goes to the lower rank; a rank no longer there is left out.
      assert %{count: 2, rank_name: "Μπλε", ranks: 2} =
               SkillNoticePolicy.notice([tick.("purple"), tick.("blue"), tick.("gone")], ranks)

      assert SkillNoticePolicy.notice([], ranks) == nil
      assert SkillNoticePolicy.notice([tick.("gone")], ranks) == nil
    end
  end

  defp elem_text(%{text: text}), do: text
  defp elem_text({_x, _y, text}), do: text
  defp elem_text(text) when is_binary(text), do: text

  defp award(id, on),
    do: %{id: id, awarded_on: on, inserted_at: ~U[2026-01-01 00:00:00Z], revoked_at: nil}

  defp rank(position, requirements),
    do: %{id: "r#{position}", position: position, requirements: requirements, max_stripes: 0}
end

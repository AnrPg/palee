defmodule Palee.ReviewAsks.Domain.ReviewReportPolicyTest do
  use ExUnit.Case, async: true

  alias Palee.ReviewAsks.Domain.ReviewReportPolicy, as: Policy

  @now ~U[2026-11-03 10:00:00.000000Z]

  describe "report/1" do
    test "a fixed reason and an optional note" do
      assert {:ok, %{reason: "offensive", note: nil}} = Policy.report(%{"reason" => "offensive"})

      assert {:ok, %{reason: "spam", note: "Διαφήμιση"}} =
               Policy.report(%{"reason" => "spam", "note" => "  Διαφήμιση "})

      assert {:error, {:invalid_fields, %{reason: "invalid"}}} =
               Policy.report(%{"reason" => "boring"})

      assert {:error, {:invalid_fields, %{reason: "invalid"}}} = Policy.report(nil)
    end

    test "illegal and other need a note, every note at most 500 characters" do
      for reason <- ~w(illegal other) do
        assert {:error, {:invalid_fields, %{note: "required"}}} =
                 Policy.report(%{"reason" => reason, "note" => "   "})

        assert {:ok, %{note: "why"}} = Policy.report(%{"reason" => reason, "note" => "why"})
      end

      assert {:error, {:invalid_fields, %{note: "too_long"}}} =
               Policy.report(%{"reason" => "offensive", "note" => String.duplicate("α", 501)})
    end
  end

  test "nobody reports their own review, nor one that is not up" do
    review = %{user_id: "a", moderation: nil}
    assert Policy.may_report(review, "a") == {:error, :cannot_report_own_review}
    assert Policy.may_report(review, "b") == :ok
    assert Policy.may_report(%{review | moderation: "hidden"}, "b") == {:error, :box_review_not_found}
  end

  test "ten reports a day per person and box" do
    assert Policy.within_limit(0) == :ok
    assert Policy.within_limit(9) == :ok
    assert Policy.within_limit(10) == {:error, :review_report_limit}
    assert Policy.limit_since(@now) == ~U[2026-11-02 10:00:00.000000Z]
  end

  test "a moderated review cannot be edited or replied to" do
    assert Policy.editable(nil) == :ok
    assert Policy.editable(%{moderation: nil}) == :ok
    assert Policy.editable(%{moderation: "removed"}) == {:error, :review_moderated}
  end

  describe "decision/1" do
    test "keep has no violation and an optional statement" do
      assert {:ok, %{outcome: "keep", ground: "no_violation", statement: nil}} =
               Policy.decision(%{"outcome" => "keep"})

      assert {:error, {:invalid_fields, %{ground: "invalid"}}} =
               Policy.decision(%{"outcome" => "keep", "ground" => "offensive"})
    end

    test "hide and remove need a ground from the reasons and a statement" do
      for outcome <- ~w(hide remove) do
        assert {:error, {:invalid_fields, %{statement: "required"}}} =
                 Policy.decision(%{"outcome" => outcome, "ground" => "offensive"})

        assert {:error, {:invalid_fields, %{ground: "invalid"}}} =
                 Policy.decision(%{
                   "outcome" => outcome,
                   "ground" => "no_violation",
                   "statement" => "x"
                 })

        assert {:ok, %{outcome: ^outcome, ground: "personal_data", statement: "Τηλέφωνο."}} =
                 Policy.decision(%{
                   "outcome" => outcome,
                   "ground" => "personal_data",
                   "statement" => " Τηλέφωνο. "
                 })
      end

      assert {:error, {:invalid_fields, %{outcome: "invalid"}}} =
               Policy.decision(%{"outcome" => "delete"})

      assert {:error, {:invalid_fields, %{statement: "too_long"}}} =
               Policy.decision(%{
                 "outcome" => "hide",
                 "ground" => "spam",
                 "statement" => String.duplicate("α", 1_001)
               })
    end
  end

  test "what each outcome does to the review and its reports" do
    assert Policy.review_changes("keep", @now) == %{moderation: nil, moderated_at: nil}
    assert Policy.review_changes("hide", @now) == %{moderation: "hidden", moderated_at: @now}

    assert %{moderation: "removed", body: nil, reply_body: nil, replied_at: nil} =
             Policy.review_changes("remove", @now)

    assert Enum.map(~w(keep hide remove), &Policy.report_status/1) == ~w(kept hidden removed)
  end

  test "the statement of reasons names the basis, a human decision and the redress" do
    decision = %{
      outcome: "remove",
      ground: "illegal",
      statement: "Απειλή.",
      reports_count: 2,
      decided_at: @now
    }

    assert %{
             legal_basis: "law",
             after_report: true,
             automated: false,
             redress: ["ask_palee_again", "court"]
           } = Policy.statement_of_reasons(decision)

    assert Policy.legal_basis("offensive") == "terms"
    assert Policy.legal_basis("no_violation") == nil
  end
end

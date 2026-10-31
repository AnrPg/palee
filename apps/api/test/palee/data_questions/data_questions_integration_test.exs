defmodule Palee.DataQuestions.IntegrationTest do
  @moduledoc """
  ADR-361 end to end below HTTP: the sandbox model picks catalogue queries,
  the SQL reader answers from the box's tables, answers are checked and
  audited; the switch, the asker's rights and the cost limits hold.
  """

  use Palee.DataCase, async: false

  import Palee.AiHelpFixtures

  alias Palee.Application.DataQuestions.DataQuestions
  alias Palee.Infrastructure.Llm.SandboxLlmProvider
  alias Palee.Llm.Domain.Response

  setup do
    on_exit(fn -> SandboxLlmProvider.script(nil) end)
    box = box_fixture()
    recent = member_fixture(box, "recent_#{System.unique_integer([:positive])}")
    away = member_fixture(box, "away_#{System.unique_integer([:positive])}")
    never = member_fixture(box, "never_#{System.unique_integer([:positive])}")
    yogi = member_fixture(box, "yogi_#{System.unique_integer([:positive])}")
    class_fixture(box, "WOD", 2, [recent])
    class_fixture(box, "WOD", 40, [away])
    class_fixture(box, "Yoga", 3, [recent, yogi], 4)
    Map.merge(box, %{recent: recent, away: away, never: never})
  end

  test "who hasn't come for 3 weeks: counted, grounded, cited; names only in the table", ctx do
    assert {:ok, answer} =
             DataQuestions.ask(ctx.context, %{
               "question" => "Who hasn't come for 3 weeks?",
               "locale" => "en"
             })

    assert answer.status == "answered"
    assert answer.grounded

    assert [%{"ref" => "q1", "query" => "members_absent", "summary" => %{"members" => 2}}] =
             answer.citations

    assert answer.answer =~ "[q1]"

    [table] = answer.tables
    names = Enum.map(table.rows, & &1["name"])
    assert ctx.never.nickname in names and ctx.away.nickname in names
    refute ctx.recent.nickname in names

    # The model never saw a name; the follow-up action carries the ids.
    refute answer.answer =~ ctx.away.nickname
    assert [%{kind: "message_people", count: 2, user_ids: ids}] = answer.actions
    assert Enum.sort(ids) == Enum.sort([ctx.away.id, ctx.never.id])

    # Audit: the queries run and the aggregates, never rows or names.
    assert {:ok, stored} = DataQuestions.show(ctx.context, answer.id)
    assert stored.queries == ["members_absent"]
    assert stored.tables == []
    refute Jason.encode!(stored) =~ ctx.away.nickname
  end

  test "revenue by package last month and attendance by class type", ctx do
    last_month =
      Date.utc_today() |> Date.beginning_of_month() |> Date.add(-1) |> Date.beginning_of_month()

    package_fixture(ctx, ctx.recent, "Unlimited", [
      {5_000, last_month},
      {4_550, Date.add(last_month, 3)}
    ])

    assert {:ok, revenue} =
             DataQuestions.ask(ctx.context, %{"question" => "Revenue by package last month"})

    assert [%{"query" => "revenue_by_package", "summary" => %{"amount" => 95.5, "payments" => 2}}] =
             revenue.citations

    assert revenue.grounded
    assert [%{rows: [%{"package" => "Unlimited", "amount_cents" => 9_550}]}] = revenue.tables

    assert {:ok, attendance} =
             DataQuestions.ask(ctx.context, %{
               "question" => "Which classes are the busiest? attendance"
             })

    [table] = attendance.tables
    yoga = Enum.find(table.rows, &(&1["class_type"] == "Yoga"))
    assert yoga["attendances"] == 2 and yoga["fill_percent"] == 50
  end

  test "an answer with numbers the data does not hold is flagged, not hidden", ctx do
    SandboxLlmProvider.script(fn request ->
      case Palee.Llm.Domain.Request.tool_results(request) do
        [] ->
          %Response{
            tool_calls: [%{id: "1", name: "member_counts", args: %{"period" => "this_month"}}]
          }

        _results ->
          %{
            "answer" => "You have 999 active members [q1]",
            "citations" => ["q1"],
            "confident" => true
          }
      end
    end)

    assert {:ok, answer} = DataQuestions.ask(ctx.context, %{"question" => "how many?"})
    assert answer.status == "answered"
    refute answer.grounded
    assert answer.unsupported_numbers == ["999"]
  end

  test "the model cannot reach a query beyond the asker's rights", ctx do
    desk = %{ctx.context | capabilities: %{view_directory: :all, view_membership_status: :all}}

    SandboxLlmProvider.script(fn request ->
      names = Enum.map(request.tools, & &1.name)
      refute "revenue_by_package" in names

      case Palee.Llm.Domain.Request.tool_results(request) do
        [] ->
          %Response{tool_calls: [%{id: "1", name: "revenue_by_package", args: %{}}]}

        [%{content: content}] ->
          assert content == %{"error" => "forbidden"}
          %{"answer" => "I can't see revenue.", "citations" => [], "confident" => false}
      end
    end)

    assert {:ok, %{status: "unanswerable", citations: []} = answer} =
             DataQuestions.ask(desk, %{"question" => "revenue?"})

    assert {:ok, %{queries: ["revenue_by_package"]}} = DataQuestions.show(desk, answer.id)
  end

  test "a coach limited to their own clients gets no gym-wide queries", ctx do
    coach = %{ctx.context | capabilities: %{view_directory: :own, view_membership_status: :own}}
    assert {:error, :forbidden} = DataQuestions.ask(coach, %{"question" => "who?"})
    assert {:ok, %{queries: []}} = DataQuestions.catalogue(coach)
  end

  test "switched off until the owner turns it on" do
    box = box_fixture(enabled: false)
    assert {:ok, %{enabled: false}} = DataQuestions.catalogue(box.context)

    assert {:error, :data_questions_disabled} =
             DataQuestions.ask(box.context, %{"question" => "who?"})
  end

  test "the daily limit refuses and audits the refusal", ctx do
    previous = Application.get_env(:palee, :ai_features)
    Application.put_env(:palee, :ai_features, data_questions: [daily_per_person: 1])
    on_exit(fn -> Application.put_env(:palee, :ai_features, previous) end)

    assert {:ok, _first} = DataQuestions.ask(ctx.context, %{"question" => "who hasn't come?"})

    assert {:error, :ai_daily_limit_reached} =
             DataQuestions.ask(ctx.context, %{"question" => "again?"})

    assert {:ok, %{questions: [refused, _first]}} = DataQuestions.list(ctx.context, %{})
    assert refused.status == "refused" and refused.error_code == "ai_daily_limit_reached"
  end

  test "the monthly budget counts metered cost of the feature", ctx do
    previous = Application.get_env(:palee, :ai_features)
    Application.put_env(:palee, :ai_features, data_questions: [monthly_budget_nano_usd: 1])
    on_exit(fn -> Application.put_env(:palee, :ai_features, previous) end)

    {:ok, _} =
      Palee.AiUsage.record_usage(ctx.context, %{
        usage: %Palee.AiUsage.Domain.TokenUsage{
          input_tokens: 1000,
          cached_input_tokens: 0,
          output_tokens: 100,
          thinking_tokens: 0
        },
        operation_id: Ecto.UUID.generate(),
        feature: "data_questions",
        provider: "gemini",
        model: "gemini-3.8-flash",
        occurred_at: DateTime.utc_now()
      })

    assert {:error, :ai_budget_exhausted} =
             DataQuestions.ask(ctx.context, %{"question" => "who?"})
  end

  test "provider failures are audited as failed", ctx do
    SandboxLlmProvider.script(fn _request -> {:error, :llm_quota_exhausted} end)

    assert {:error, :llm_quota_exhausted} =
             DataQuestions.ask(ctx.context, %{"question" => "who?"})

    assert {:ok, %{questions: [%{status: "failed", error_code: "llm_quota_exhausted"}]}} =
             DataQuestions.list(ctx.context, %{})
  end

  test "the box's audit log is for owners and admins", ctx do
    {:ok, _} = DataQuestions.ask(ctx.context, %{"question" => "who hasn't come?"})
    other = %{ctx.context | user_id: Ecto.UUID.generate(), capabilities: %{view_directory: :all}}

    assert {:error, :forbidden} = DataQuestions.list(other, %{"scope" => "all"})
    assert {:ok, %{questions: []}} = DataQuestions.list(other, %{})
    assert {:ok, %{questions: [_]}} = DataQuestions.list(ctx.context, %{"scope" => "all"})
  end
end

defmodule Palee.Llm.DomainTest do
  @moduledoc "ADR-360: the tool loop, budgets and untrusted-data cleaning, pure."

  use ExUnit.Case, async: true

  alias Palee.AiUsage.Domain.TokenUsage
  alias Palee.Llm.Domain.{Budget, Request, Response, Tool, ToolLoop, Untrusted}

  defp usage(input, output),
    do: %TokenUsage{
      input_tokens: input,
      cached_input_tokens: 0,
      output_tokens: output,
      thinking_tokens: 0
    }

  defp tool(name),
    do: Tool.new(%{name: name, description: "d", input_schema: %{"type" => "object"}})

  describe "ToolLoop" do
    test "runs tool calls, sends results back and returns the final answer with steps and usage" do
      request = %Request{messages: [%{role: :user, text: "q"}], tools: [tool("count")]}

      generate = fn
        %Request{messages: [_user]} ->
          {:ok,
           %Response{
             tool_calls: [%{id: "a", name: "count", args: %{"n" => 2}}],
             usage: usage(10, 2)
           }}

        %Request{messages: [_user, %{role: :assistant}, %{role: :tool, results: [result]}]} ->
          assert result.content == %{"value" => 4}
          {:ok, %Response{text: ~s({"answer":"4"}), usage: usage(20, 3)}}
      end

      execute = fn "count", %{"n" => n}, step ->
        {:ok, %{"value" => n * 2}, %{ref: "q#{step}"}}
      end

      assert {:ok, run} = ToolLoop.run(request, generate, execute)
      assert run.response.text == ~s({"answer":"4"})
      assert run.rounds == 1
      assert [%{step: 1, tool: "count", args: %{"n" => 2}, ref: "q1"}] = run.steps
      assert run.usage.input_tokens == 30 and run.usage.output_tokens == 5
    end

    test "a failing tool is reported to the model, never raised" do
      request = %Request{messages: [%{role: :user, text: "q"}], tools: [tool("xx")]}

      generate = fn
        %Request{messages: [_]} ->
          {:ok, %Response{tool_calls: [%{id: "a", name: "xx", args: %{}}]}}

        %Request{messages: [_, _, %{results: [%{content: content}]}]} ->
          assert content == %{"error" => "forbidden"}
          {:ok, %Response{text: "{}"}}
      end

      assert {:ok, %{steps: [%{error: "forbidden"}]}} =
               ToolLoop.run(request, generate, fn _, _, _ -> {:error, :forbidden} end)
    end

    test "turns calling off after the round budget and refuses calls after it" do
      request = %Request{messages: [%{role: :user, text: "q"}], tools: [tool("xx")]}
      parent = self()

      generate = fn %Request{tool_choice: choice} ->
        send(parent, {:choice, choice})
        {:ok, %Response{tool_calls: [%{id: "a", name: "xx", args: %{}}]}}
      end

      assert {:error, :llm_invalid_answer} =
               ToolLoop.run(request, generate, fn _, _, _ -> {:ok, %{}, %{}} end, max_rounds: 1)

      assert_received {:choice, :auto}
      assert_received {:choice, :none}
    end

    test "answers beyond the per-round call budget get too_many_calls" do
      request = %Request{messages: [%{role: :user, text: "q"}], tools: [tool("xx")]}
      calls = for i <- 1..3, do: %{id: "c#{i}", name: "xx", args: %{}}

      generate = fn
        %Request{messages: [_]} -> {:ok, %Response{tool_calls: calls}}
        _later -> {:ok, %Response{text: "{}"}}
      end

      assert {:ok, %{steps: steps}} =
               ToolLoop.run(request, generate, fn _, _, _ -> {:ok, %{}, %{}} end,
                 max_calls_per_round: 2
               )

      assert [%{step: 1}, %{step: 2}, %{step: 3, error: "too_many_calls"}] = steps
    end

    test "provider errors stop the loop" do
      assert {:error, :llm_unavailable} =
               ToolLoop.run(%Request{}, fn _ -> {:error, :llm_unavailable} end, fn _, _, _ ->
                 :ok
               end)
    end
  end

  describe "Budget" do
    test "refuses past the monthly budget or the daily count; nil limits are off" do
      limits = Budget.limits(monthly_budget_nano_usd: 100, daily_per_person: 3)

      assert :ok = Budget.check(limits, %{spent_nano_usd: 99, used_today: 2})

      assert {:error, :ai_budget_exhausted} =
               Budget.check(limits, %{spent_nano_usd: 100, used_today: 0})

      assert {:error, :ai_daily_limit_reached} =
               Budget.check(limits, %{spent_nano_usd: 0, used_today: 3})

      assert :ok =
               Budget.check(Budget.limits([]), %{spent_nano_usd: 10 ** 12, used_today: 10 ** 6})

      assert Budget.remaining(limits, 130) == 0
    end

    test "windows are the UTC month and day" do
      %{month_start: month, day_start: day} = Budget.windows(~U[2026-10-31 18:00:00Z])
      assert month == ~U[2026-10-01 00:00:00Z]
      assert day == ~U[2026-10-31 00:00:00Z]
    end
  end

  describe "Untrusted" do
    test "removes control and bidi characters, collapses whitespace and caps length" do
      assert Untrusted.text("a" <> <<0x202E::utf8>> <> "b\u0000c \n\n d", 100) == "abc d"
      assert Untrusted.text(String.duplicate("x", 20), 10) == String.duplicate("x", 9) <> "…"

      assert Untrusted.data(%{"n" => "x​y", "d" => ~D[2026-01-02], "list" => [1, "a\tb"]}) ==
               %{"n" => "xy", "d" => "2026-01-02", "list" => [1, "a b"]}
    end
  end

  describe "Response.json" do
    test "reads an object with fences or prose around it" do
      assert {:ok, %{"a" => 1}} = Response.json(%Response{text: "```json\n{\"a\":1}\n```"})
      assert {:ok, %{"a" => 1}} = Response.json(%Response{text: "Here: {\"a\":1} ok"})
      assert {:error, :invalid_answer} = Response.json(%Response{text: "no"})
      assert {:error, :invalid_answer} = Response.json(%Response{text: nil})
    end
  end

  test "tool names are checked" do
    assert_raise ArgumentError, fn -> tool("Bad Name") end
  end
end

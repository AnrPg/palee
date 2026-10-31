defmodule Palee.Llm.Domain.ToolLoop do
  @moduledoc """
  The tool-calling loop (ADR-360), pure: the model call and the tool
  executor are injected, so the loop has no IO of its own and is the same
  for every provider and feature.

  Each round sends the request; tool calls are executed (at most
  `max_calls_per_round` per round, the rest are answered with an error)
  and sent back; after `max_rounds` tool rounds calling is switched off
  (`tool_choice: :none`) so the model must answer. The loop returns the
  final response and a step log for the audit: one entry per tool call
  with its name, arguments and the executor's `audit` summary.

  A tool executor returns `{:ok, content, audit}` or `{:error, code}`;
  either way the model is told, and the loop goes on. The model never
  sees an exception.
  """

  alias Palee.AiUsage.Domain.TokenUsage
  alias Palee.Llm.Domain.{Request, Response}

  @type generate :: (Request.t() -> {:ok, Response.t()} | {:error, term()})
  @type execute :: (String.t(), map() -> {:ok, map(), map()} | {:error, atom()})

  @type result :: %{
          response: Response.t(),
          request: Request.t(),
          steps: [map()],
          usage: TokenUsage.t(),
          rounds: non_neg_integer()
        }

  @spec run(Request.t(), generate(), execute(), keyword()) :: {:ok, result()} | {:error, term()}
  def run(%Request{} = request, generate, execute, opts \\ [])
      when is_function(generate, 1) and is_function(execute, 2) do
    state = %{
      max_rounds: Keyword.get(opts, :max_rounds, 3),
      max_calls: Keyword.get(opts, :max_calls_per_round, 4),
      steps: [],
      usage: TokenUsage.zero(),
      rounds: 0
    }

    loop(request, generate, execute, state)
  end

  defp loop(request, generate, execute, state) do
    final? = state.rounds >= state.max_rounds or request.tools == []
    request = if final?, do: %{request | tool_choice: :none}, else: request

    with {:ok, %Response{} = response} <- generate.(request) do
      state = %{state | usage: add_usage(state.usage, response.usage)}

      case response.tool_calls do
        [] ->
          {:ok,
           %{
             response: response,
             request: request,
             steps: Enum.reverse(state.steps),
             usage: state.usage,
             rounds: state.rounds
           }}

        _calls when final? ->
          {:error, :llm_invalid_answer}

        calls ->
          {results, steps} = execute_calls(calls, execute, state)

          request = %{
            request
            | messages:
                request.messages ++
                  [
                    %{
                      role: :assistant,
                      text: response.text,
                      tool_calls: calls,
                      turn: response.turn
                    },
                    %{role: :tool, results: results}
                  ]
          }

          loop(request, generate, execute, %{
            state
            | steps: Enum.reverse(steps) ++ state.steps,
              rounds: state.rounds + 1
          })
      end
    end
  end

  defp execute_calls(calls, execute, state) do
    calls
    |> Enum.with_index()
    |> Enum.map(fn {call, index} ->
      step_number = length(state.steps) + index + 1

      {content, audit} =
        if index < state.max_calls do
          case execute.(call.name, call.args || %{}) do
            {:ok, content, audit} -> {content, audit}
            {:error, code} -> {%{"error" => to_string(code)}, %{error: to_string(code)}}
          end
        else
          {%{"error" => "too_many_calls"}, %{error: "too_many_calls"}}
        end

      result = %{id: call.id, name: call.name, content: content}

      step =
        Map.merge(
          %{step: step_number, tool: call.name, args: call.args || %{}},
          audit
        )

      {result, step}
    end)
    |> Enum.unzip()
  end

  defp add_usage(total, nil), do: total

  defp add_usage(%TokenUsage{} = total, %TokenUsage{} = usage) do
    %TokenUsage{
      input_tokens: total.input_tokens + usage.input_tokens,
      cached_input_tokens: total.cached_input_tokens + usage.cached_input_tokens,
      output_tokens: total.output_tokens + usage.output_tokens,
      thinking_tokens: total.thinking_tokens + usage.thinking_tokens
    }
  end
end

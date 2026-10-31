defmodule Palee.Infrastructure.Llm.SandboxLlmProvider do
  @moduledoc """
  Deterministic `LlmProvider` for dev and tests (ADR-360). No network, no
  key, the same answer for the same request.

  Default behaviour:

    * with tools and no tool result yet, it calls the tool whose name and
      `keywords` share most words with the user's latest message (no
      arguments, so the tool's defaults apply); none matching, it answers
      that it cannot tell;
    * after tool results, it answers by quoting each result's numbers and
      citing the result's `ref`;
    * with documents, it answers from the document sharing most words with
      the question and cites it; none sharing a word, it is not confident.

  The answer is the JSON object `{"answer", "citations", "confident"}`.

  Tests can script any answer for the current process with
  `script/1` (a function from the `Request` to `{:ok, Response}`,
  `{:error, reason}` or a plain map that becomes the JSON answer).
  Usage is reported to `Palee.AiUsage` as provider and model `sandbox`
  (unpriced), so metering runs the same path as in production.
  """

  @behaviour Palee.Llm.Ports.LlmProvider

  alias Palee.AiUsage
  alias Palee.AiUsage.Domain.TokenUsage
  alias Palee.Llm.Domain.{Request, Response, Tool}

  @script_key {__MODULE__, :script}

  @doc "Scripts this process's answers (a fun of the request); `nil` clears it."
  def script(nil), do: Process.delete(@script_key)
  def script(fun) when is_function(fun, 1), do: Process.put(@script_key, fun)

  @impl true
  def generate(%Request{} = request, options) do
    result =
      case Process.get(@script_key) do
        nil -> {:ok, default(request)}
        fun -> wrap(fun.(request))
      end

    with {:ok, %Response{} = response} <- result do
      usage = usage(request, response)
      meter(usage, options)
      {:ok, %{response | usage: usage, model: "sandbox"}}
    end
  end

  defp wrap({:ok, %Response{}} = ok), do: ok
  defp wrap({:error, _reason} = error), do: error
  defp wrap(%Response{} = response), do: {:ok, response}
  defp wrap(%{} = answer), do: {:ok, %Response{text: Jason.encode!(answer)}}

  defp default(%Request{} = request) do
    results = Request.tool_results(request)
    question = Request.last_user_text(request)

    cond do
      request.tools != [] and request.tool_choice == :auto and results == [] ->
        case best_tool(request.tools, question) do
          nil -> answer("", [], false)
          tool -> %Response{tool_calls: [%{id: "call_1", name: tool.name, args: %{}}]}
        end

      results != [] ->
        from_results(results)

      request.documents != [] ->
        from_documents(request.documents, question)

      true ->
        answer("", [], false)
    end
  end

  defp best_tool(tools, question) do
    words = words(question)

    tools
    |> Enum.map(fn %Tool{} = tool ->
      vocabulary = words(Enum.join([tool.name | tool.keywords], " "))
      {MapSet.size(MapSet.intersection(words, vocabulary)), tool}
    end)
    |> Enum.filter(fn {score, _tool} -> score > 0 end)
    |> Enum.max_by(fn {score, _tool} -> score end, fn -> nil end)
    |> case do
      {_score, tool} -> tool
      nil -> nil
    end
  end

  defp from_results(results) do
    {lines, refs} =
      results
      |> Enum.reject(&Map.has_key?(&1.content, "error"))
      |> Enum.map(fn result ->
        ref = Map.get(result.content, "ref", result.id)
        numbers = numbers(Map.get(result.content, "summary", result.content))
        {"#{result.name}: #{numbers} [#{ref}]", ref}
      end)
      |> Enum.unzip()

    answer(Enum.join(lines, "; "), refs, refs != [])
  end

  defp numbers(%{} = summary) do
    summary
    |> Enum.filter(fn {_key, value} -> is_integer(value) end)
    |> Enum.sort()
    |> Enum.map_join(", ", fn {key, value} -> "#{key} #{value}" end)
  end

  defp numbers(_other), do: ""

  defp from_documents(documents, question) do
    words = words(question)

    documents
    |> Enum.map(fn document ->
      vocabulary = words(document.title <> " " <> document.text)
      {MapSet.size(MapSet.intersection(words, vocabulary)), document}
    end)
    |> Enum.filter(fn {score, _document} -> score > 0 end)
    |> Enum.max_by(fn {score, _document} -> score end, fn -> nil end)
    |> case do
      {_score, document} ->
        answer("#{document.title}: #{String.slice(document.text, 0, 240)}", [document.id], true)

      nil ->
        answer("", [], false)
    end
  end

  defp answer(text, citations, confident),
    do: %Response{
      text: Jason.encode!(%{answer: text, citations: citations, confident: confident})
    }

  defp words(text) do
    text
    |> String.downcase()
    |> String.split(~r/[^\p{L}\p{N}]+/u, trim: true)
    |> Enum.filter(&(String.length(&1) > 2))
    |> MapSet.new()
  end

  defp usage(request, response) do
    prompt = byte_size(request.system) + byte_size(:erlang.term_to_binary(request.messages))
    output = byte_size(response.text || "") + 20 * length(response.tool_calls)

    %TokenUsage{
      input_tokens: div(prompt, 4),
      cached_input_tokens: 0,
      output_tokens: div(output, 4),
      thinking_tokens: 0
    }
  end

  defp meter(usage, options) do
    AiUsage.report_generation(
      usage,
      0,
      options
      |> AiUsage.metering()
      |> Map.merge(%{
        provider: "sandbox",
        model: "sandbox",
        model_version: nil,
        agent: Map.get(options, :agent, "assistant"),
        occurred_at: DateTime.utc_now()
      })
    )
  end
end

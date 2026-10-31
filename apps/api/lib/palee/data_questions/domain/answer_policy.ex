defmodule Palee.DataQuestions.Domain.AnswerPolicy do
  @moduledoc """
  Validates the model's final answer (ADR-361), pure: the JSON object of
  `Prompt.answer_schema/0`, citations limited to refs that were actually
  returned, the text cleaned and capped. Decides the stored status:
  `answered` or `unanswerable` (the model said the queries cannot answer).
  """

  alias Palee.Llm.Domain.Untrusted

  @max_answer 2_000
  @max_question 500

  def max_question, do: @max_question

  @doc "Validates the question text."
  def question(text) when is_binary(text) do
    cleaned = Untrusted.text(text, @max_question + 1)

    cond do
      cleaned == "" -> {:error, {:invalid_fields, %{question: ["required"]}}}
      String.length(cleaned) > @max_question -> {:error, {:invalid_fields, %{question: ["too_long"]}}}
      true -> {:ok, cleaned}
    end
  end

  def question(_text), do: {:error, {:invalid_fields, %{question: ["required"]}}}

  @doc "`{:ok, %{status, answer, citations}}` or `{:error, :llm_invalid_answer}`."
  def evaluate(%{"answer" => answer} = json, known_refs) when is_binary(answer) do
    citations =
      json
      |> Map.get("citations", [])
      |> List.wrap()
      |> Enum.filter(&(is_binary(&1) and &1 in known_refs))
      |> Enum.uniq()

    text = Untrusted.text(answer, @max_answer)
    confident = Map.get(json, "confident") != false

    status =
      if confident and text != "" and citations != [],
        do: "answered",
        else: "unanswerable"

    {:ok, %{status: status, answer: text, citations: citations}}
  end

  def evaluate(_json, _known_refs), do: {:error, :llm_invalid_answer}
end

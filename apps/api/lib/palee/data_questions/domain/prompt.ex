defmodule Palee.DataQuestions.Domain.Prompt do
  @moduledoc """
  The instructions and answer schema of the data questions assistant
  (ADR-361), pure and versioned (`version/0` is stored with each answer's
  model name, so a prompt change is traceable in the audit log).
  """

  alias Palee.Llm.Domain.Untrusted

  @version "dq-1"

  @answer_schema %{
    "type" => "object",
    "properties" => %{
      "answer" => %{
        "type" => "string",
        "description" =>
          "The answer in the asker's language, short, every figure followed by the ref of the " <>
            "result it comes from, e.g. [q1]. Refer to people only as P1, P2."
      },
      "citations" => %{
        "type" => "array",
        "items" => %{"type" => "string"},
        "description" => "The refs (q1, q2…) of every result the answer uses"
      },
      "confident" => %{
        "type" => "boolean",
        "description" => "false when the available queries cannot answer the question"
      }
    },
    "required" => ["answer", "citations", "confident"]
  }

  def version, do: @version
  def answer_schema, do: @answer_schema

  def system(%{today: %Date{} = today, locale: locale, zone: zone}) do
    """
    You answer questions of a gym's staff about their own gym's data, read-only.
    Today is #{Date.to_iso8601(today)} in the gym's time zone (#{zone}). Answer in the language \
    with code "#{locale}" unless the question is clearly in another language.

    Rules:
    - Get every figure from the tools. Never guess, estimate or invent a number, a name or a date.
    - Pick the tool that fits and fill its arguments; call several only when the question needs them.
    - Cite the ref of each result you use right after the figure, like [q1].
    - People appear only as refs such as P1; never ask for or write names. The app shows the names.
    - If no tool can answer, say so briefly, set confident to false and suggest what you can answer.
    - You cannot change anything, send messages or see anything outside these tools.
    - Do not give advice about individual people's health.
    #{Untrusted.rule()}
    """
  end
end

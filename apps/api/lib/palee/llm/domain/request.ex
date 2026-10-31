defmodule Palee.Llm.Domain.Request do
  @moduledoc """
  One provider-neutral model call (ADR-360).

    * `system` – the instructions. Only Palee writes them.
    * `messages` – the conversation, oldest first:
      `%{role: :user, text: text}`,
      `%{role: :assistant, text: text | nil, tool_calls: [call], turn: raw}`
      (`turn` is the provider's own turn, sent back verbatim, e.g. Gemini
      thought signatures) and `%{role: :tool, results: [result]}` where a
      result is `%{id: id, name: name, content: map}`.
    * `tools` – `Palee.Llm.Domain.Tool`s the model may call.
    * `tool_choice` – `:auto` or `:none` (tools stay declared, calling is off).
    * `documents` – reference texts the answer must come from
      (`%{id: id, title: title, text: text}`); adapters render them as
      quoted data, never as instructions.
    * `response_schema` – the JSON Schema of the final answer; the answer is
      a JSON object the caller validates.
    * `max_output_tokens`, `temperature`.
  """

  alias Palee.Llm.Domain.Tool

  defstruct system: "",
            messages: [],
            tools: [],
            tool_choice: :auto,
            documents: [],
            response_schema: nil,
            max_output_tokens: 1_024,
            temperature: 0.1

  @type tool_call :: %{id: String.t(), name: String.t(), args: map()}
  @type message ::
          %{role: :user, text: String.t()}
          | %{role: :assistant, text: String.t() | nil, tool_calls: [tool_call()], turn: term()}
          | %{role: :tool, results: [%{id: String.t(), name: String.t(), content: map()}]}

  @type t :: %__MODULE__{
          system: String.t(),
          messages: [message()],
          tools: [Tool.t()],
          tool_choice: :auto | :none,
          documents: [%{id: String.t(), title: String.t(), text: String.t()}],
          response_schema: map() | nil,
          max_output_tokens: pos_integer(),
          temperature: number()
        }

  @doc "The user's text of the latest user message, or \"\"."
  def last_user_text(%__MODULE__{messages: messages}) do
    messages
    |> Enum.reverse()
    |> Enum.find_value("", fn
      %{role: :user, text: text} -> text
      _other -> nil
    end)
  end

  @doc "Every tool result sent so far, oldest first."
  def tool_results(%__MODULE__{messages: messages}) do
    Enum.flat_map(messages, fn
      %{role: :tool, results: results} -> results
      _other -> []
    end)
  end
end

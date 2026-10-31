defmodule Palee.Llm.Domain.Response do
  @moduledoc """
  What a provider answered to one `Request` (ADR-360): either tool calls or
  a final text (a JSON object when the request had a `response_schema`),
  with the billed usage and the provider's raw turn (sent back verbatim on
  the next round).
  """

  alias Palee.AiUsage.Domain.TokenUsage

  defstruct text: nil, tool_calls: [], usage: nil, model: nil, turn: nil

  @type t :: %__MODULE__{
          text: String.t() | nil,
          tool_calls: [%{id: String.t(), name: String.t(), args: map()}],
          usage: TokenUsage.t() | nil,
          model: String.t() | nil,
          turn: term()
        }

  @doc """
  Decodes the final text as one JSON object, tolerating code fences or
  prose around it. `{:error, :invalid_answer}` otherwise.
  """
  def json(%__MODULE__{text: text}) when is_binary(text) do
    trimmed = text |> String.trim() |> String.replace(~r/^```(?:json)?\s*|\s*```$/u, "")

    case Jason.decode(trimmed) do
      {:ok, %{} = decoded} ->
        {:ok, decoded}

      _other ->
        with [object] <- Regex.run(~r/\{.*\}/su, trimmed),
             {:ok, %{} = decoded} <- Jason.decode(object) do
          {:ok, decoded}
        else
          _invalid -> {:error, :invalid_answer}
        end
    end
  end

  def json(_response), do: {:error, :invalid_answer}
end

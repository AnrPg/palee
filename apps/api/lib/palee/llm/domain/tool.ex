defmodule Palee.Llm.Domain.Tool do
  @moduledoc """
  A tool a model may call (ADR-360): a name, a description written for the
  model (when to use it, when not), and the JSON Schema of its arguments.

  Provider adapters convert it to their own shape (Gemini
  `functionDeclarations`, Anthropic `tools`); nothing else restates the
  schema. It carries the same fields as a v4 operation spec (ADR-300), so a
  registry operation can be turned into a tool without a second schema.

  `keywords` are plain words that hint when the tool fits; only the
  deterministic sandbox adapter reads them.
  """

  @enforce_keys [:name, :description, :input_schema]
  defstruct [:name, :description, :input_schema, keywords: []]

  @type t :: %__MODULE__{
          name: String.t(),
          description: String.t(),
          input_schema: map(),
          keywords: [String.t()]
        }

  @name_pattern ~r/^[a-z][a-z0-9_]{1,63}$/

  @doc "Builds a tool, checking the name is safe for every provider."
  def new(attrs) do
    tool = struct!(__MODULE__, attrs)

    if Regex.match?(@name_pattern, tool.name),
      do: tool,
      else: raise(ArgumentError, "invalid tool name #{inspect(tool.name)}")
  end
end

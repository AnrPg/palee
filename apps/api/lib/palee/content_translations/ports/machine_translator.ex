defmodule Palee.ContentTranslations.Ports.MachineTranslator do
  @moduledoc """
  ADR-520: translates a batch of a business's texts from one language into
  another. Only the texts themselves (and the business's name, kept as it
  is) are sent, never any person's data.

  `texts` are `%{id, kind, text}` (`kind` like `"package.name"` gives the
  model context). Answers `{:ok, %{id => translated}}`, possibly without
  some ids, or `{:error, :not_configured | term()}`.
  """

  @type request :: %{
          from: String.t(),
          to: String.t(),
          business_name: String.t() | nil,
          texts: [%{id: String.t(), kind: String.t(), text: String.t()}]
        }

  @callback available?() :: boolean()
  @callback translate(request(), metering :: map()) ::
              {:ok, %{String.t() => String.t()}} | {:error, term()}
end

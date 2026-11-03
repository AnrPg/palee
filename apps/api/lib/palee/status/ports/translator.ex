defmodule Palee.Status.Ports.Translator do
  @moduledoc """
  ADR-366: translates an incident's title and note into English and says
  which language they were written in. Only the text the Palee team wrote is
  sent, never any person's data.

  `{:ok, %{locale, title, body}}` (`locale` is the detected source language,
  e.g. `"el"`; `title` is nil when none was sent) or `{:error, reason}`; the
  caller publishes without English when it fails.
  """

  @type text :: %{required(:body) => String.t(), optional(:title) => String.t() | nil}
  @type result :: %{locale: String.t() | nil, title: String.t() | nil, body: String.t()}

  @callback to_english(text(), metering :: map()) :: {:ok, result()} | {:error, term()}
end

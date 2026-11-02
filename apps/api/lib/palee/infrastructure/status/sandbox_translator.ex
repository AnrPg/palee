defmodule Palee.Infrastructure.Status.SandboxTranslator do
  @moduledoc """
  ADR-366: the translator for dev and test. Text with Greek letters is
  treated as Greek and "translated" by prefixing `[EN] `; anything else is
  treated as English and returned as it is.
  `config :palee, :status_sandbox_translation, {:error, reason}` makes it fail.
  """

  @behaviour Palee.Status.Ports.Translator

  @impl true
  def to_english(%{body: body} = text, _metering) do
    case Application.get_env(:palee, :status_sandbox_translation) do
      {:error, _reason} = error ->
        error

      _translate ->
        title = Map.get(text, :title)

        if greek?(body) or greek?(title),
          do: {:ok, %{locale: "el", title: title && "[EN] " <> title, body: "[EN] " <> body}},
          else: {:ok, %{locale: "en", title: title, body: body}}
    end
  end

  defp greek?(text) when is_binary(text), do: Regex.match?(~r/\p{Greek}/u, text)
  defp greek?(_text), do: false
end

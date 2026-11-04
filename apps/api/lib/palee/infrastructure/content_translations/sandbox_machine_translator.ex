defmodule Palee.Infrastructure.ContentTranslations.SandboxMachineTranslator do
  @moduledoc """
  ADR-500: the machine translator for dev and test. Each text comes back
  prefixed with the target language (`[EN] …`).

  `config :palee, :content_sandbox_translation, ...`: `:unavailable` makes it
  not configured, `{:error, reason}` makes every call fail, `{:skip, n}`
  leaves out every n-th answer.
  """

  @behaviour Palee.ContentTranslations.Ports.MachineTranslator

  @impl true
  def available?, do: Application.get_env(:palee, :content_sandbox_translation) != :unavailable

  @impl true
  def translate(%{to: to, texts: texts}, _metering) do
    case Application.get_env(:palee, :content_sandbox_translation) do
      :unavailable ->
        {:error, :not_configured}

      {:error, _reason} = error ->
        error

      setting ->
        skip = with {:skip, n} <- setting, do: n

        answers =
          texts
          |> Enum.with_index(1)
          |> Enum.reject(fn {_text, index} -> is_integer(skip) and rem(index, skip) == 0 end)
          |> Map.new(fn {%{id: id, text: text}, _index} ->
            {id, "[#{String.upcase(to)}] " <> text}
          end)

        {:ok, answers}
    end
  end
end

defmodule Palee.Infrastructure.Status.GeminiTranslator do
  @moduledoc """
  ADR-366: translates a status page incident into English with Google Gemini
  (the platform's `GEMINI_API_KEY`, model `GEMINI_TRANSLATE_MODEL`, default
  `gemini-2.5-flash-lite`). Only the title and note the Palee team wrote are
  sent. Without a key it answers `{:error, :not_configured}` and the console
  publishes without English. Every answered call is metered (ADR-152).
  """

  @behaviour Palee.Status.Ports.Translator

  alias Palee.AiUsage

  @endpoint "https://generativelanguage.googleapis.com/v1beta/models"
  @default_model "gemini-2.5-flash-lite"

  @instructions """
  You translate notices on the public status page of Palee, an app for gyms.
  The Palee team wrote the notice in any language. Translate the title and the
  note into plain, calm British English. Keep times, numbers, product names
  and component names as they are. Do not add, remove or soften anything.
  Reply with JSON only: {"locale": "<ISO 639-1 code of the source language>",
  "title": "<English title, or null when no title was given>",
  "body": "<English note>"}. If the text is already English, return it as it is
  with "locale": "en".
  """

  @impl true
  def to_english(%{body: body} = text, metering) when is_binary(body) do
    config = Application.get_env(:palee, :gemini, [])

    case Keyword.get(config, :api_key) do
      key when is_binary(key) and key != "" ->
        request(
          key,
          Keyword.get(config, :translate_model) || @default_model,
          config,
          text,
          metering
        )

      _missing ->
        {:error, :not_configured}
    end
  end

  defp request(key, model, config, text, metering) do
    prompt =
      Jason.encode!(%{title: Map.get(text, :title), body: text.body})

    body = %{
      systemInstruction: %{parts: [%{text: @instructions}]},
      contents: [%{role: "user", parts: [%{text: prompt}]}],
      generationConfig: %{
        temperature: 0.1,
        maxOutputTokens: 2048,
        responseMimeType: "application/json",
        thinkingConfig: %{thinkingBudget: 0}
      }
    }

    started = System.monotonic_time(:millisecond)

    response =
      Req.post(
        [
          url: "#{@endpoint}/#{model}:generateContent",
          json: body,
          headers: [{"x-goog-api-key", key}],
          receive_timeout: 15_000,
          retry: false
        ]
        |> Keyword.merge(Keyword.get(config, :req_options, []))
      )

    meter(response, model, metering, System.monotonic_time(:millisecond) - started)

    case response do
      {:ok, %Req.Response{status: 200, body: %{"candidates" => [candidate | _]}}} ->
        candidate |> extract_text() |> decode()

      {:ok, %Req.Response{status: status}} ->
        {:error, {:gemini_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp decode({:ok, text}) do
    case Jason.decode(text) do
      {:ok, %{"body" => body} = answer} when is_binary(body) ->
        {:ok,
         %{
           locale: string(answer["locale"]),
           title: string(answer["title"]),
           body: body
         }}

      _other ->
        {:error, :unreadable_translation}
    end
  end

  defp decode({:error, _reason} = error), do: error

  defp string(value) when is_binary(value), do: value
  defp string(_value), do: nil

  defp extract_text(%{"content" => %{"parts" => [%{"text" => text} | _]}}), do: {:ok, text}
  defp extract_text(_candidate), do: {:error, :empty_translation}

  # ADR-152: every answered call is billed, whatever its text.
  defp meter({:ok, %Req.Response{status: 200, body: %{} = body}}, model, metering, duration_ms) do
    case AiUsage.token_usage_from_gemini(Map.get(body, "usageMetadata")) do
      nil ->
        :ok

      usage ->
        AiUsage.report_generation(
          usage,
          duration_ms,
          metering
          |> AiUsage.metering_context()
          |> Map.merge(%{
            provider: "gemini",
            model: model,
            model_version: Map.get(body, "modelVersion"),
            agent: "status_translation",
            occurred_at: DateTime.utc_now()
          })
        )
    end
  end

  defp meter(_response, _model, _metering, _duration_ms), do: :ok
end

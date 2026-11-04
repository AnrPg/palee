defmodule Palee.Infrastructure.ContentTranslations.GeminiMachineTranslator do
  @moduledoc """
  ADR-520: translates a business's website texts with Google Gemini (the
  platform's `GEMINI_API_KEY`, model `GEMINI_TRANSLATE_MODEL`, default
  `gemini-2.5-flash-lite`). Only the texts and the business's name are sent.
  Without a key it is not available and answers `{:error, :not_configured}`.
  Every answered call is metered (ADR-152) to the business.
  """

  @behaviour Palee.ContentTranslations.Ports.MachineTranslator

  alias Palee.AiUsage

  @endpoint "https://generativelanguage.googleapis.com/v1beta/models"
  @default_model "gemini-2.5-flash-lite"

  @instructions """
  You translate the website texts of a gym or fitness business for visitors.
  You get JSON {"from", "to", "business", "texts": [{"id", "kind", "text"}]}
  where "from" and "to" are language codes and "kind" says what the text is
  (for example "package.name", "site_faq.answer", "class_type.name").
  Translate every text from "from" into natural, friendly "to", as a local
  gym would write it. Keep the business name, people's names, brand names,
  exercise and workout names that are usually left in English (WOD, AMRAP,
  EMOM, CrossFit, Open box), prices, numbers, times, emoji and line breaks.
  Do not add, remove or explain anything. Short names stay short.
  Reply with JSON only: {"texts": [{"id": "<same id>", "text": "<translation>"}]}.
  """

  @impl true
  def available? do
    case Keyword.get(config(), :api_key) do
      key when is_binary(key) and key != "" -> true
      _missing -> false
    end
  end

  @impl true
  def translate(%{texts: []}, _metering), do: {:ok, %{}}

  def translate(request, metering) do
    config = config()

    if available?(),
      do:
        request(
          Keyword.fetch!(config, :api_key),
          Keyword.get(config, :translate_model) || @default_model,
          config,
          request,
          metering
        ),
      else: {:error, :not_configured}
  end

  defp config, do: Application.get_env(:palee, :gemini, [])

  defp request(key, model, config, request, metering) do
    prompt =
      Jason.encode!(%{
        from: request.from,
        to: request.to,
        business: request[:business_name],
        texts: Enum.map(request.texts, &Map.take(&1, [:id, :kind, :text]))
      })

    body = %{
      systemInstruction: %{parts: [%{text: @instructions}]},
      contents: [%{role: "user", parts: [%{text: prompt}]}],
      generationConfig: %{
        temperature: 0.2,
        maxOutputTokens: 8192,
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
          receive_timeout: 45_000,
          retry: false
        ]
        |> Keyword.merge(Keyword.get(config, :req_options, []))
      )

    meter(response, model, metering, System.monotonic_time(:millisecond) - started)

    case response do
      {:ok, %Req.Response{status: 200, body: %{"candidates" => [candidate | _]}}} ->
        candidate |> extract_text() |> decode(request.texts)

      {:ok, %Req.Response{status: status}} ->
        {:error, {:gemini_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp decode({:ok, text}, texts) do
    wanted = MapSet.new(texts, & &1.id)

    case Jason.decode(text) do
      {:ok, %{"texts" => answers}} when is_list(answers) ->
        translated =
          for %{"id" => id, "text" => text} <- answers,
              is_binary(id) and is_binary(text) and MapSet.member?(wanted, id),
              into: %{},
              do: {id, text}

        {:ok, translated}

      _other ->
        {:error, :unreadable_translation}
    end
  end

  defp decode({:error, _reason} = error, _texts), do: error

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
            agent: "site_translation",
            occurred_at: DateTime.utc_now()
          })
        )
    end
  end

  defp meter(_response, _model, _metering, _duration_ms), do: :ok
end

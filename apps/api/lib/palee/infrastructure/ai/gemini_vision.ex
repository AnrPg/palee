defmodule Palee.Infrastructure.Ai.GeminiVision do
  @moduledoc """
  One Gemini call about one image (ADR-157): alternative text and the
  automatic photo check share it. Without `GEMINI_API_KEY` it answers
  `{:error, :not_configured}`. Every answered call is metered (ADR-152).
  Only the photo and a fixed instruction are sent — never who posted it.
  """

  alias Palee.AiUsage

  @endpoint "https://generativelanguage.googleapis.com/v1beta/models"
  @default_model "gemini-2.5-flash-lite"

  @doc "Whether a Gemini key is set (ADR-421 hides «Φωτογραφία ετικέτας» without one)."
  def configured? do
    case :palee |> Application.get_env(:gemini, []) |> Keyword.get(:api_key) do
      key when is_binary(key) and key != "" -> true
      _missing -> false
    end
  end

  @doc "`{:ok, text}` of the model's answer about one image, or a list of them (ADR-421)."
  def generate(image, instructions, prompt, generation_config, metering, agent) do
    config = Application.get_env(:palee, :gemini, [])

    case Keyword.get(config, :api_key) do
      key when is_binary(key) and key != "" ->
        model = Keyword.get(config, :vision_model) || @default_model

        request(
          key,
          model,
          config,
          image,
          instructions,
          prompt,
          generation_config,
          metering,
          agent
        )

      _missing ->
        {:error, :not_configured}
    end
  end

  defp request(
         key,
         model,
         config,
         image,
         instructions,
         prompt,
         generation_config,
         metering,
         agent
       ) do
    body = %{
      systemInstruction: %{parts: [%{text: instructions}]},
      contents: [
        %{
          role: "user",
          parts:
            Enum.map(List.wrap(image), fn image ->
              %{inlineData: %{mimeType: image.content_type, data: Base.encode64(image.bytes)}}
            end) ++ [%{text: prompt}]
        }
      ],
      generationConfig: Map.merge(%{thinkingConfig: %{thinkingBudget: 0}}, generation_config)
    }

    started = System.monotonic_time(:millisecond)

    response =
      Req.post(
        [
          url: "#{@endpoint}/#{model}:generateContent",
          json: body,
          headers: [{"x-goog-api-key", key}],
          receive_timeout: 20_000,
          retry: false
        ]
        |> Keyword.merge(Keyword.get(config, :req_options, []))
      )

    meter(response, model, metering, agent, System.monotonic_time(:millisecond) - started)

    case response do
      {:ok, %Req.Response{status: 200, body: %{"candidates" => [candidate | _]}}} ->
        extract_text(candidate)

      {:ok, %Req.Response{status: 200, body: %{"promptFeedback" => %{"blockReason" => reason}}}} ->
        {:ok, {:blocked, reason}}

      {:ok, %Req.Response{status: status}} ->
        {:error, {:gemini_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp meter({:ok, %Req.Response{status: 200, body: %{} = body}}, model, metering, agent, ms) do
    case AiUsage.token_usage_from_gemini(Map.get(body, "usageMetadata")) do
      nil ->
        :ok

      usage ->
        AiUsage.report_generation(
          usage,
          ms,
          metering
          |> AiUsage.metering_context()
          |> Map.merge(%{
            provider: "gemini",
            model: model,
            model_version: Map.get(body, "modelVersion"),
            agent: agent,
            occurred_at: DateTime.utc_now()
          })
        )
    end
  end

  defp meter(_response, _model, _metering, _agent, _ms), do: :ok

  defp extract_text(%{"content" => %{"parts" => [%{"text" => text} | _]}}), do: {:ok, text}

  defp extract_text(%{"finishReason" => reason}) when reason in ["SAFETY", "PROHIBITED_CONTENT"],
    do: {:ok, {:blocked, reason}}

  defp extract_text(_candidate), do: {:error, :empty_answer}
end

defmodule Palee.FakeLogDraftParser do
  @moduledoc """
  Test stand-in behind the `LogDraftParser` port (ADR-175). Deterministic:
  answers a fixed draft for any transcript. Tells the calling process what
  it was asked (`{:log_draft_parser_called, input, options}`). Keys
  starting with `rejected` answer as a rejected key, `invalid` as an
  unusable answer. A usable answer is metered like the real adapter
  (agent `voice_parse`, 1000 input and 200 output tokens).
  """

  @behaviour Palee.VoiceLog.Ports.LogDraftParser

  alias Palee.AiUsage
  alias Palee.AiUsage.Domain.TokenUsage

  @impl true
  def parse(input, options) do
    send(self(), {:log_draft_parser_called, input, options})

    case Map.get(options, :api_key) do
      nil ->
        {:error, :parser_not_configured}

      "rejected" <> _rest ->
        {:error, :parser_key_rejected}

      "invalid" <> _rest ->
        {:ok, %{"exercises" => "not a list"}}

      _key ->
        meter(options)
        {:ok, answer()}
    end
  end

  defp meter(options) do
    AiUsage.report_generation(
      %TokenUsage{
        input_tokens: 1000,
        cached_input_tokens: 0,
        output_tokens: 200,
        thinking_tokens: 0
      },
      5,
      options
      |> AiUsage.metering()
      |> Map.merge(%{
        provider: "anthropic",
        model: "claude-sonnet-5-5",
        model_version: "claude-sonnet-5-5",
        agent: "voice_parse",
        occurred_at: DateTime.utc_now()
      })
    )
  end

  defp answer do
    %{
      "title" => "Squats και κωπηλατική",
      "duration_minutes" => 45,
      "perceived_effort" => 7,
      "days_ago" => 0,
      "notes" => nil,
      "exercises" => [
        %{"name" => "Back Squat", "sets" => 5, "reps" => 5, "load" => 100, "load_unit" => "kg"},
        %{"name" => "Row", "sets" => nil, "reps" => nil, "load" => nil, "load_unit" => nil},
        %{"name" => "  ", "sets" => 3, "reps" => 3, "load" => nil, "load_unit" => nil}
      ]
    }
  end
end

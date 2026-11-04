defmodule Palee.Application.GymAiSettings do
  @moduledoc """
  The gym's AI settings (ADR-174): read and write the switch for scaling
  suggestions, the gym's own key (write-only) and an optional model, plus
  this month's metered usage the key paid for (ADR-152): scaling
  suggestions and voice drafts.
  """

  alias Palee.Application.{ScalingSuggestions, VoiceLogDrafts}
  alias Palee.{AiUsage, Scaling}

  def get(context, now \\ DateTime.utc_now()) do
    context
    |> AiUsage.get_settings()
    |> AiUsage.public_settings(Scaling.default_model())
    |> Map.put(:usage, month_usage(context, now))
  end

  def update(context, params, now \\ DateTime.utc_now()) do
    current = AiUsage.get_settings(context)

    with {:ok, changes} <- AiUsage.settings_update_changes(current, params, context.user_id),
         {:ok, _settings} <- AiUsage.put_settings(context, changes) do
      {:ok, get(context, now)}
    end
  end

  # The current calendar month (UTC): what the gym's own key paid for, i.e.
  # scaling suggestions and voice drafts (the Claude step only: the speech to
  # text step runs on the platform's key and is not billed to the gym's key).
  defp month_usage(context, now) do
    from = %{DateTime.truncate(now, :second) | day: 1, hour: 0, minute: 0, second: 0}

    scaling = AiUsage.usage_summary(context, %{from: from, feature: ScalingSuggestions.feature()})

    voice =
      AiUsage.usage_summary(context, %{
        from: from,
        feature: VoiceLogDrafts.feature(),
        agent: "voice_parse"
      })

    %{
      since: from,
      suggestions: operations(scaling),
      voice_drafts: operations(voice),
      cost_usd: (scaling.cost_usd || 0.0) + (voice.cost_usd || 0.0)
    }
  end

  defp operations(summary), do: summary.rows |> Enum.map(& &1.operations) |> Enum.sum()
end

defmodule Palee.Llm.Domain.Budget do
  @moduledoc """
  Cost limits of an AI feature (ADR-360), pure. Two limits, both checked
  before a model is called:

    * a monthly budget per box, in nano-USD, against what the feature has
      already cost the box this calendar month (UTC), as metered by
      `Palee.AiUsage` (ADR-152);
    * a daily count per person (questions or messages), so one person
      cannot spend the box's budget alone.

  A limit that is `nil` is off. Limits come from config per feature:

      config :palee, :ai_features,
        data_questions: [monthly_budget_nano_usd: 5_000_000_000, daily_per_person: 30]
  """

  @type limits :: %{
          optional(:monthly_budget_nano_usd) => non_neg_integer() | nil,
          optional(:daily_per_person) => non_neg_integer() | nil
        }

  @spec check(limits(), %{spent_nano_usd: non_neg_integer(), used_today: non_neg_integer()}) ::
          :ok | {:error, :ai_budget_exhausted | :ai_daily_limit_reached}
  def check(limits, %{spent_nano_usd: spent, used_today: used}) do
    cond do
      over?(Map.get(limits, :monthly_budget_nano_usd), spent) -> {:error, :ai_budget_exhausted}
      over?(Map.get(limits, :daily_per_person), used) -> {:error, :ai_daily_limit_reached}
      true -> :ok
    end
  end

  @doc "Limits from a keyword list or map (config), unknown keys dropped."
  def limits(config) when is_list(config), do: config |> Map.new() |> limits()

  def limits(%{} = config) do
    %{
      monthly_budget_nano_usd: non_negative(Map.get(config, :monthly_budget_nano_usd)),
      daily_per_person: non_negative(Map.get(config, :daily_per_person))
    }
  end

  def limits(_config), do: %{monthly_budget_nano_usd: nil, daily_per_person: nil}

  @doc "Start of the UTC calendar month and of the UTC day that hold `now`."
  def windows(%DateTime{} = now) do
    date = DateTime.to_date(now)
    month = Date.beginning_of_month(date)

    %{
      month_start: DateTime.new!(month, ~T[00:00:00], "Etc/UTC"),
      day_start: DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
    }
  end

  @doc "What is left of the monthly budget, or nil when unlimited."
  def remaining(limits, spent) do
    case Map.get(limits, :monthly_budget_nano_usd) do
      nil -> nil
      cap -> max(cap - spent, 0)
    end
  end

  defp over?(nil, _used), do: false
  defp over?(cap, used), do: used >= cap

  defp non_negative(value) when is_integer(value) and value >= 0, do: value
  defp non_negative(_value), do: nil
end

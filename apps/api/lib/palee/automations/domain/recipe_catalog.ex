defmodule Palee.Automations.Domain.RecipeCatalog do
  @moduledoc """
  ADR-346: the ready recipes. A box does not build automations; it switches
  these on («Ενεργό») and may change each one's text, channels, delay and a
  setting or two. Every recipe is off until the box switches it on.

  Each recipe names:

    * `trigger` - a domain event (`{:event, name}`) or the daily scan
      (`:daily`), run once a day per box after `send_hour` in the box's time
      zone;
    * `audience` - who it reaches: `:member` (a person with a Palee profile:
      box members and trial visitors) or also `:lead`;
    * `purpose` - `:service` (about something the person has or asked for)
      or `:marketing` (birthday, win-back). Marketing needs the lead's
      marketing consent; box members get it under the soft opt-in of
      existing customers (ePrivacy art. 13(2)) with an opt-out in every
      message and in the app;
    * `delay_minutes` - after the trigger (events), before quiet hours;
    * `channels` - default order; the first one that reaches the person is
      used;
    * `settings` - what a box may tune, with defaults and bounds.

  Texts live in `Palee.Automations.Domain.RecipeTexts`.
  """

  @quiet_from "21:00"
  @quiet_until "09:00"

  @recipes [
    %{
      key: "welcome",
      trigger: {:event, :membership_activated},
      audience: [:member],
      purpose: :service,
      delay_minutes: 60,
      channels: ["in_app", "email"],
      settings: %{}
    },
    %{
      key: "trial_follow_up",
      trigger: {:event, :trial_attended},
      audience: [:member, :lead],
      purpose: :service,
      delay_minutes: 1_440,
      channels: ["in_app", "email"],
      settings: %{}
    },
    %{
      key: "missed_classes",
      trigger: :daily,
      audience: [:member],
      purpose: :service,
      delay_minutes: 0,
      channels: ["in_app", "email"],
      settings: %{"days_absent" => {10, 5..60}}
    },
    %{
      key: "renewal_reminder",
      trigger: :daily,
      audience: [:member],
      purpose: :service,
      delay_minutes: 0,
      channels: ["in_app", "email"],
      settings: %{"days_before" => {5, 1..30}}
    },
    %{
      key: "birthday",
      trigger: :daily,
      audience: [:member],
      purpose: :marketing,
      delay_minutes: 0,
      channels: ["in_app", "email"],
      settings: %{}
    },
    %{
      key: "win_back",
      trigger: {:event, :member_at_risk},
      audience: [:member],
      purpose: :marketing,
      delay_minutes: 0,
      channels: ["in_app", "email"],
      settings: %{}
    }
  ]

  @by_key Map.new(@recipes, &{&1.key, &1})

  # Every recipe sends its daily messages at this local hour (unless the
  # box picks another, «Προχωρημένα»).
  @default_send_hour 10

  def all, do: @recipes
  def keys, do: Enum.map(@recipes, & &1.key)
  def default_send_hour, do: @default_send_hour
  def default_quiet_hours, do: %{"quiet_from" => @quiet_from, "quiet_until" => @quiet_until}

  @spec fetch(String.t()) :: {:ok, map()} | {:error, :unknown_recipe}
  def fetch(key) do
    case Map.fetch(@by_key, key) do
      {:ok, recipe} -> {:ok, recipe}
      :error -> {:error, :unknown_recipe}
    end
  end

  def get!(key), do: Map.fetch!(@by_key, key)

  @doc "Recipes started by the domain event `name`."
  def for_event(name), do: Enum.filter(@recipes, &(&1.trigger == {:event, name}))

  @doc "Recipes the daily scan runs."
  def daily, do: Enum.filter(@recipes, &(&1.trigger == :daily))

  @doc """
  A recipe's settings with the box's stored ones applied: its own numbers
  (bounded), the quiet hours and the daily send hour.
  """
  def settings(recipe, stored) do
    stored = stored || %{}

    own =
      Map.new(recipe.settings, fn {name, {default, range}} ->
        {name, bounded(Map.get(stored, name), default, range)}
      end)

    own
    |> Map.merge(default_quiet_hours())
    |> Map.merge(Map.take(stored, ["quiet_from", "quiet_until"]))
    |> Map.put("send_hour", bounded(Map.get(stored, "send_hour"), @default_send_hour, 6..21))
  end

  @doc """
  Validates a box's change of settings for `recipe`: its own numbers within
  bounds, quiet hours as `HH:MM`, `send_hour` from 6 to 21.
  """
  @spec validate_settings(map(), map()) :: {:ok, map()} | {:error, {:invalid_fields, map()}}
  def validate_settings(recipe, params) when is_map(params) do
    errors =
      Enum.reduce(params, %{}, fn {name, value}, errors ->
        case check(recipe, to_string(name), value) do
          :ok -> errors
          :error -> Map.put(errors, "settings.#{name}", "invalid")
        end
      end)

    if errors == %{},
      do: {:ok, Map.new(params, fn {name, value} -> {to_string(name), value} end)},
      else: {:error, {:invalid_fields, errors}}
  end

  def validate_settings(_recipe, _params),
    do: {:error, {:invalid_fields, %{"settings" => "invalid"}}}

  defp check(_recipe, name, value) when name in ["quiet_from", "quiet_until"],
    do: if(clock_time?(value), do: :ok, else: :error)

  defp check(_recipe, "send_hour", value) when is_integer(value) and value in 6..21, do: :ok

  defp check(recipe, name, value) when is_integer(value) do
    case Map.fetch(recipe.settings, name) do
      {:ok, {_default, range}} -> if value in range, do: :ok, else: :error
      :error -> :error
    end
  end

  defp check(_recipe, _name, _value), do: :error

  defp clock_time?(value) when is_binary(value),
    do: Regex.match?(~r/^([01]\d|2[0-3]):[0-5]\d$/, value)

  defp clock_time?(_value), do: false

  defp bounded(value, default, range) when is_integer(value),
    do: if(value in range, do: value, else: default)

  defp bounded(_value, default, _range), do: default
end

defmodule Palee.Automations.Domain.DeliveryPolicy do
  @moduledoc """
  ADR-346: whether one automatic message may go now, decided again when it
  is sent (a person may have opted out, a box switched the recipe off,
  consent changed since it was queued). Pure.

    * the recipe must still be on for the box;
    * the person must be someone the recipe is for, and still there;
    * a box member who opted out of all automatic messages of this box, or
      of this recipe, gets nothing;
    * a lead needs contact consent; marketing recipes also need marketing
      consent not withdrawn since;
    * inside quiet hours the message waits for their end.

  Failed sends are retried with growing waits, at most `max_attempts/0`.
  """

  alias Palee.Automations.Domain.QuietHours

  @max_attempts 5
  @base_backoff_seconds 300

  @statuses ~w(pending sending sent skipped failed cancelled)

  def statuses, do: @statuses
  def max_attempts, do: @max_attempts

  @doc """
  `{:send, channels}`, `{:defer, at}`, `{:skip, reason}` or
  `{:cancel, reason}` for a claimed delivery. `facts`:

    * `recipe` (catalog entry), `automation` (the box's row or nil),
      `settings` (resolved), `channels` (the box's order);
    * `recipient` - `%{kind: :member | :lead, ...}` or nil;
    * `preferences` - the member's choices at this box, or nil;
    * `time_zone`, `now`.
  """
  def decide(%{automation: automation}) when automation in [nil, false],
    do: {:cancel, "recipe_off"}

  def decide(%{automation: %{enabled: false}}), do: {:cancel, "recipe_off"}
  def decide(%{recipient: nil}), do: {:skip, "recipient_gone"}

  def decide(%{recipe: recipe, recipient: recipient} = facts) do
    with :ok <- audience(recipe, recipient),
         :ok <- allowed(recipe, recipient, Map.get(facts, :preferences)),
         :ok <- quiet(facts) do
      {:send, facts.channels}
    end
  end

  defp audience(recipe, %{kind: kind}),
    do: if(kind in recipe.audience, do: :ok, else: {:skip, "audience"})

  defp allowed(recipe, %{kind: :member}, preferences) do
    cond do
      opted_out_all?(preferences) -> {:skip, "opted_out"}
      recipe.key in opted_out_recipes(preferences) -> {:skip, "opted_out"}
      true -> :ok
    end
  end

  defp allowed(recipe, %{kind: :lead} = lead, _preferences) do
    cond do
      is_nil(lead[:consent_contact_at]) ->
        {:skip, "no_consent"}

      recipe.purpose == :marketing and
          (is_nil(lead[:consent_marketing_at]) or not is_nil(lead[:marketing_opted_out_at])) ->
        {:skip, "no_marketing_consent"}

      true ->
        :ok
    end
  end

  defp opted_out_all?(%{opted_out_at: %DateTime{}}), do: true
  defp opted_out_all?(_preferences), do: false

  defp opted_out_recipes(%{opted_out_recipes: recipes}) when is_list(recipes), do: recipes
  defp opted_out_recipes(_preferences), do: []

  defp quiet(%{settings: settings, time_zone: zone, now: now}) do
    allowed = QuietHours.next_allowed(now, zone, settings["quiet_from"], settings["quiet_until"])
    if DateTime.compare(allowed, now) == :gt, do: {:defer, allowed}, else: :ok
  end

  @doc """
  When a delivery triggered at `at` is due: after the recipe's delay, moved
  out of quiet hours.
  """
  def due_at(%DateTime{} = at, delay_minutes, settings, time_zone) do
    at
    |> DateTime.add(delay_minutes * 60, :second)
    |> QuietHours.next_allowed(time_zone, settings["quiet_from"], settings["quiet_until"])
  end

  @doc "After a failed attempt: `{:retry, at}` or `:give_up`."
  def after_failure(attempts, %DateTime{} = now) when attempts < @max_attempts,
    do: {:retry, DateTime.add(now, @base_backoff_seconds * Integer.pow(2, max(attempts, 1) - 1), :second)}

  def after_failure(_attempts, _now), do: :give_up
end

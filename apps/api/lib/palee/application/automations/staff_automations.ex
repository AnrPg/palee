defmodule Palee.Application.Automations.StaffAutomations do
  @moduledoc """
  ADR-346: the box's «Αυτοματισμοί» (`PaleeWeb.AdminAutomationController`).
  The ready recipes, each with its switch, text, channels and delay; a
  preview of the message; and what was sent lately. Switching a recipe off
  cancels what it had queued.
  """

  alias Palee.{Automations, Identity, Leads, Organizations}

  @stats_days 30

  @doc "Every recipe as the box has it, its defaults in `locale`, and the last 30 days' counts."
  def index(context, locale \\ "el") do
    automations = context |> Automations.list_automations() |> Map.new(&{&1.recipe, &1})
    since = DateTime.add(Automations.now(), -@stats_days, :day)
    stats = Automations.delivery_stats(context, since)

    %{
      recipes:
        Enum.map(
          Automations.recipes(),
          &present(&1, Map.get(automations, &1.key), Map.get(stats, &1.key, %{}), locale)
        ),
      channels: Automations.channel_names(),
      placeholders: Automations.placeholders(),
      stats_days: @stats_days
    }
  end

  @doc """
  Changes one recipe: `enabled`, `channels` (ordered, from the deployment's
  channels), `delay_minutes` (event recipes), `subject` and `body` (blank
  for the default), `settings`.
  """
  def update(context, recipe_key, params, locale \\ "el") do
    with {:ok, recipe} <- Automations.fetch_recipe(recipe_key),
         {:ok, attrs} <- attrs(recipe, params),
         {:ok, saved} <-
           Automations.put_automation(
             context,
             recipe_key,
             Map.put(attrs, :updated_by_id, Map.get(context, :user_id))
           ) do
      unless saved.enabled do
        Automations.cancel_pending(context, %{recipe: recipe_key, reason: "recipe_off"})
      end

      stats = Automations.delivery_stats(context, DateTime.add(Automations.now(), -@stats_days, :day))
      {:ok, present(recipe, saved, Map.get(stats, recipe_key, %{}), locale)}
    end
  end

  defp attrs(recipe, params) do
    Enum.reduce_while(params, {:ok, %{}}, fn {key, value}, {:ok, acc} ->
      case attr(recipe, to_string(key), value) do
        {:ok, field, cast} -> {:cont, {:ok, Map.put(acc, field, cast)}}
        :ignore -> {:cont, {:ok, acc}}
        {:error, field} -> {:halt, {:error, {:invalid_fields, %{field => "invalid"}}}}
      end
    end)
  end

  defp attr(_recipe, "enabled", value) when is_boolean(value), do: {:ok, :enabled, value}

  defp attr(_recipe, "channels", channels) when is_list(channels) and channels != [] do
    if Enum.all?(channels, &(&1 in Automations.channel_names())) and
         Enum.uniq(channels) == channels,
       do: {:ok, :channels, channels},
       else: {:error, "channels"}
  end

  defp attr(_recipe, "delay_minutes", nil), do: {:ok, :delay_minutes, nil}

  defp attr(%{trigger: {:event, _name}}, "delay_minutes", minutes)
       when is_integer(minutes) and minutes in 0..43_200,
       do: {:ok, :delay_minutes, minutes}

  defp attr(_recipe, field, text) when field in ["subject", "body"] do
    case Automations.validate_text(text, String.to_existing_atom(field)) do
      {:ok, text} -> {:ok, String.to_existing_atom(field), text}
      {:error, _reason} -> {:error, field}
    end
  end

  defp attr(recipe, "settings", settings) when is_map(settings) do
    case Automations.validate_settings(recipe, settings) do
      {:ok, settings} -> {:ok, :settings, settings}
      {:error, _invalid} -> {:error, "settings"}
    end
  end

  defp attr(_recipe, "recipe", _value), do: :ignore
  defp attr(_recipe, field, _value), do: {:error, field}

  @doc "The message as a person would get it, with a sample name, in `locale`."
  def preview(context, recipe_key, params) do
    locale = params["locale"] || "el"

    with {:ok, recipe} <- Automations.fetch_recipe(recipe_key) do
      automation = Automations.get_automation(context, recipe_key)
      {subject, body} = Automations.default_text(recipe_key, locale)

      vars = %{
        "first_name" => params["first_name"] || sample_name(locale),
        "box" => box_name(context),
        "days" => 10,
        "package" => sample_package(locale),
        "ends_on" => context |> today() |> Date.add(5) |> Calendar.strftime("%d/%m/%Y")
      }

      {:ok,
       %{
         recipe: recipe.key,
         subject: Automations.render(params["subject"] || (automation && automation.subject) || subject, vars),
         body: Automations.render(params["body"] || (automation && automation.body) || body, vars)
       }}
    end
  end

  defp sample_name("el"), do: "Μαρία"
  defp sample_name(_locale), do: "Maria"

  defp sample_package("el"), do: "Μηνιαίο απεριόριστο"
  defp sample_package(_locale), do: "Monthly unlimited"

  @doc "Recent messages, newest first, with whom each one was for."
  def deliveries(context, params) do
    filters =
      %{
        recipe: params["recipe"],
        status: params["status"],
        limit: limit(params["limit"])
      }
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()

    deliveries = Automations.list_deliveries(context, filters)

    people =
      deliveries
      |> Enum.map(& &1.user_id)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> case do
        [] -> %{}
        ids -> ids |> Identity.list_by_ids() |> Map.new(&{&1.id, &1.nickname})
      end

    leads =
      deliveries
      |> Enum.map(& &1.lead_id)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Map.new(&{&1, context |> Leads.get(&1) |> then(fn lead -> lead && lead.name end)})

    Enum.map(deliveries, fn delivery ->
      %{
        id: delivery.id,
        recipe: delivery.recipe,
        status: delivery.status,
        channel: delivery.channel,
        due_at: delivery.due_at,
        sent_at: delivery.sent_at,
        skip_reason: delivery.skip_reason,
        attempts: delivery.attempts,
        recipient: %{
          kind: if(delivery.user_id, do: "member", else: "lead"),
          user_id: delivery.user_id,
          lead_id: delivery.lead_id,
          name: Map.get(people, delivery.user_id) || Map.get(leads, delivery.lead_id)
        }
      }
    end)
  end

  defp limit(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} -> n
      _other -> 50
    end
  end

  defp limit(_value), do: 50

  @doc "A recipe as the API shows it."
  def present(recipe, automation, stats, locale) do
    {subject, body} = Automations.default_text(recipe.key, locale)

    %{
      key: recipe.key,
      trigger: trigger(recipe.trigger),
      audience: Enum.map(recipe.audience, &to_string/1),
      purpose: to_string(recipe.purpose),
      enabled: (automation && automation.enabled) || false,
      channels: channels(recipe, automation),
      default_channels: recipe.channels,
      delay_minutes: (automation && automation.delay_minutes) || recipe.delay_minutes,
      default_delay_minutes: recipe.delay_minutes,
      subject: automation && automation.subject,
      body: automation && automation.body,
      default_subject: subject,
      default_body: body,
      settings: Automations.settings(recipe, automation && automation.settings),
      updated_at: automation && automation.updated_at,
      stats: Map.new(~w(pending sent skipped failed cancelled), &{&1, Map.get(stats, &1, 0)})
    }
  end

  defp channels(_recipe, %{channels: [_ | _] = channels}), do: channels
  defp channels(recipe, _automation), do: recipe.channels

  defp trigger({:event, name}), do: to_string(name)
  defp trigger(:daily), do: "daily"

  defp box_name(%{organization_id: organization_id}) do
    case Organizations.get_by_id(organization_id) do
      %{name: name} -> name
      _none -> ""
    end
  end

  defp today(%{organization_id: organization_id}),
    do: Organizations.local_today(organization_id, Automations.now())
end

defmodule Palee.Application.Automations.MyAutomationPreferences do
  @moduledoc """
  ADR-346: a box member's own choices about the box's automatic messages
  (their «Αυτόματα μηνύματα» settings): none at all, or not from
  some recipes, and the birthday (day and month only) they choose to share
  for the birthday greeting. Opting out cancels what was already queued.
  """

  alias Palee.Automations

  @doc "The member's choices at this box, with the recipes they can turn off."
  def show(%{user_id: user_id} = context) do
    present(Automations.get_preference(context, user_id))
  end

  @doc """
  Changes the member's choices: `opted_out` (all automatic messages of this
  box), `opted_out_recipes`, `birthday` (`%{month, day}` or null to stop
  sharing it).
  """
  def update(%{user_id: user_id} = context, params) do
    now = Automations.now()
    current = Automations.get_preference(context, user_id)

    with {:ok, attrs} <- attrs(current, params, now),
         {:ok, saved} <- Automations.put_preference(context, user_id, attrs) do
      cancel_queued(context, user_id, saved)
      {:ok, present(saved)}
    else
      {:error, %Ecto.Changeset{}} -> {:error, {:invalid_fields, %{"birthday" => "invalid"}}}
      error -> error
    end
  end

  defp attrs(current, params, now) do
    with {:ok, birthday} <- birthday(params) do
      attrs =
        %{}
        |> put_opt_out(current, params, now)
        |> put_recipes(params)
        |> Map.merge(birthday)

      {:ok, attrs}
    end
  end

  defp put_opt_out(attrs, current, %{"opted_out" => true}, now),
    do: Map.put(attrs, :opted_out_at, (current && current.opted_out_at) || now)

  defp put_opt_out(attrs, _current, %{"opted_out" => false}, _now),
    do: Map.put(attrs, :opted_out_at, nil)

  defp put_opt_out(attrs, _current, _params, _now), do: attrs

  defp put_recipes(attrs, %{"opted_out_recipes" => recipes}) when is_list(recipes),
    do: Map.put(attrs, :opted_out_recipes, Enum.uniq(recipes))

  defp put_recipes(attrs, _params), do: attrs

  defp birthday(%{"birthday" => nil}), do: {:ok, %{birthday_month: nil, birthday_day: nil}}

  defp birthday(%{"birthday" => %{"month" => month, "day" => day}})
       when is_integer(month) and is_integer(day),
       do: {:ok, %{birthday_month: month, birthday_day: day}}

  defp birthday(%{"birthday" => _invalid}),
    do: {:error, {:invalid_fields, %{"birthday" => "invalid"}}}

  defp birthday(_params), do: {:ok, %{}}

  defp cancel_queued(context, user_id, %{opted_out_at: %DateTime{}}),
    do: Automations.cancel_pending(context, %{user_id: user_id, reason: "opted_out"})

  defp cancel_queued(context, user_id, %{opted_out_recipes: recipes}) do
    Enum.each(recipes, fn recipe ->
      Automations.cancel_pending(context, %{user_id: user_id, recipe: recipe, reason: "opted_out"})
    end)
  end

  defp present(nil),
    do:
      present(%{opted_out_at: nil, opted_out_recipes: [], birthday_month: nil, birthday_day: nil})

  defp present(preference) do
    %{
      opted_out: not is_nil(preference.opted_out_at),
      opted_out_recipes: preference.opted_out_recipes || [],
      birthday:
        if(preference.birthday_month,
          do: %{month: preference.birthday_month, day: preference.birthday_day}
        ),
      recipes: Enum.map(Automations.recipes(), &%{key: &1.key, purpose: to_string(&1.purpose)})
    }
  end
end

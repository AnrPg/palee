defmodule Palee.BoxSite.Domain.SiteSections do
  @moduledoc """
  ADR-352: the sections of a box's website. Each is a key whose content comes
  from data the box already has; the owner only orders them and hides some.
  A section with no data is hidden by the renderer, so the default needs no
  setting up.
  """

  @keys ~w(hero about schedule packages coaches location reviews faq trial_form contact_form)

  @doc "Every section key, in the default order."
  def keys, do: @keys

  @doc """
  The owner's order with any unknown key dropped, duplicates removed and
  missing keys appended in default order (so a new section shows up on
  existing sites). `hero` always comes first.
  """
  def normalize_order(order) when is_list(order) do
    known = order |> Enum.filter(&(&1 in @keys)) |> Enum.uniq()
    ordered = known ++ (@keys -- known)
    ["hero" | List.delete(ordered, "hero")]
  end

  def normalize_order(_order), do: @keys

  @doc "Validates the owner's choice: `{:ok, %{order, hidden}}` or `{:error, field}`."
  def validate(order, hidden) do
    cond do
      not valid_list?(order) -> {:error, :section_order}
      not valid_list?(hidden) -> {:error, :hidden_sections}
      "hero" in hidden -> {:error, :hidden_sections}
      true -> {:ok, %{order: normalize_order(order), hidden: Enum.uniq(hidden)}}
    end
  end

  defp valid_list?(list), do: is_list(list) and Enum.all?(list, &(&1 in @keys))

  @doc """
  The sections a visitor sees, in order: the owner's order without hidden
  ones, and without those whose switch is off (`facts`: `public_schedule`,
  `faq?`, `forms_enabled`, `reviews?`).
  """
  def visible(order, hidden, facts) do
    order
    |> normalize_order()
    |> Enum.reject(&(&1 in hidden))
    |> Enum.filter(&available?(&1, facts))
  end

  defp available?("schedule", facts), do: Map.get(facts, :public_schedule, false)
  defp available?("faq", facts), do: Map.get(facts, :faq?, false)
  defp available?("reviews", facts), do: Map.get(facts, :reviews?, false)

  defp available?(form, facts) when form in ["trial_form", "contact_form"],
    do: Map.get(facts, :forms_enabled, false)

  defp available?(_key, _facts), do: true
end

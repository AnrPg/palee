defmodule Palee.BoxSite.Domain.SiteSections do
  @moduledoc """
  ADR-352: the sections of a box's website. Each is a key whose content comes
  from data the box already has; the owner only orders them and hides some.
  A section with no data is hidden by the renderer, so the default needs no
  setting up.

  ADR-388 (v3.1) adds `events` (the box's events open to everyone) and `wod`
  («WOD της ημέρας», off until the owner turns `public_wod` on, like the
  timetable). Existing sites get them appended to their order.

  ADR-530 adds `photos` («Φωτογραφίες»: the box page photos and the room
  photos marked public), `stats` («Αριθμοί κοινότητας»: aggregates only) and
  `programmes` («Προγράμματα»: programmes for sale). Every section is now an
  on/off switch: each template has its own flow, so the order is kept only
  for the old settings and `normalize_order/1`.
  """

  @keys ~w(hero about photos stats schedule events wod programmes packages coaches location reviews faq trial_form contact_form)

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
  ones, and without those whose switch is off or that have nothing to show
  (`facts`: `public_schedule`, `public_wod`, `faq?`, `forms_enabled`,
  `reviews?`, `photos?`, `stats?`, `programmes?`; a missing fact is off).
  `hero` always comes first.
  """
  def visible(order, hidden, facts) do
    order
    |> normalize_order()
    |> Enum.reject(&(&1 in hidden and &1 != "packages"))
    |> Enum.filter(&available?(&1, facts))
  end

  defp available?("schedule", facts), do: Map.get(facts, :public_schedule, false)
  defp available?("wod", facts), do: Map.get(facts, :public_wod, false)
  defp available?("faq", facts), do: Map.get(facts, :faq?, false)
  defp available?("reviews", facts), do: Map.get(facts, :reviews?, false)
  defp available?("photos", facts), do: Map.get(facts, :photos?, false)
  defp available?("stats", facts), do: Map.get(facts, :stats?, false)
  defp available?("programmes", facts), do: Map.get(facts, :programmes?, false)
  # ADR-553: shown when someone not signed in sees a package; the switch is
  # the box's «Ποιος βλέπει τα πακέτα», so the website never hides it itself.
  defp available?("packages", facts), do: Map.get(facts, :packages?, true)

  defp available?(form, facts) when form in ["trial_form", "contact_form"],
    do: Map.get(facts, :forms_enabled, false)

  defp available?(_key, _facts), do: true
end

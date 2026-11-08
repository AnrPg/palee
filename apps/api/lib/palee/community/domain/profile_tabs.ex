defmodule Palee.Community.Domain.ProfileTabs do
  @moduledoc """
  ADR-554: the tabs of a profile. «Πολυμέσα · Αναρτήσεις» are always there
  and come first; the owner adds the optional ones from their journal with
  «+ Καρτέλα» (PRs, Διακρίσεις), in the order they added them. Pure rules,
  no I/O.
  """

  @fixed ~w(media posts)
  @optional ~w(prs badges)
  @bio_max 150

  def fixed, do: @fixed
  def optional, do: @optional
  def bio_max, do: @bio_max

  @doc "The tabs a profile shows, fixed first, then the stored optional ones in order."
  def shown(stored) when is_list(stored), do: @fixed ++ normalize(stored)
  def shown(_stored), do: @fixed

  @doc "Known optional tabs only, each once, in the order given."
  def normalize(tabs) when is_list(tabs),
    do: tabs |> Enum.filter(&(&1 in @optional)) |> Enum.uniq()

  def normalize(_tabs), do: []

  @doc "«Λίγα λόγια»: trimmed, blank as none."
  def bio(nil), do: nil

  def bio(text) when is_binary(text) do
    case String.trim(text) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  def bio(_text), do: nil
end

defmodule Palee.Channels.Margins do
  @moduledoc """
  Palee's margin on the messages it sends for a box on its own provider
  account (ADR-369): a platform setting the Palee team edits in the vendor
  console, in basis points per channel (`sms`, `email`, and `viber`,
  `whatsapp` for when they come). 0 until set.

  The box pays the provider's price plus the margin (`CostPolicy.price/2`);
  a box on its own provider account pays no margin and nothing to Palee.
  """

  alias Palee.Channels.ChannelStore
  alias Palee.Channels.Domain.CostPolicy

  @doc "`%{margins_bps, updated_at, updated_by_id}` (every channel, 0 when unset)."
  def get do
    settings = ChannelStore.get_platform_settings() || %{}
    {:ok, margins} = CostPolicy.validate_margins(%{})

    %{
      margins_bps: Map.merge(margins, valid(Map.get(settings, :margins_bps) || %{})),
      updated_at: Map.get(settings, :updated_at),
      updated_by_id: Map.get(settings, :updated_by_id)
    }
  end

  @doc "The margin on `channel` now."
  def bps(channel), do: CostPolicy.margin_bps(get().margins_bps, channel)

  @doc """
  Saves margins (`%{"sms" => 2500}`; channels not sent keep theirs).
  `{:ok, settings}` or `{:error, {:invalid_fields, errors}}`.
  """
  def save(params, actor_id) do
    current = get().margins_bps

    with {:ok, margins} <- CostPolicy.validate_margins(params),
         sent = Map.take(margins, Enum.map(Map.keys(params), &to_string/1)),
         {:ok, _saved} <-
           ChannelStore.save_platform_settings(%{
             margins_bps: Map.merge(current, sent),
             updated_by_id: actor_id
           }) do
      {:ok, get()}
    end
  end

  # A stored value Palee no longer accepts counts as unset.
  defp valid(stored) do
    stored
    |> Enum.filter(fn {channel, bps} ->
      channel in CostPolicy.margin_channels() and is_integer(bps) and bps >= 0
    end)
    |> Map.new()
  end
end

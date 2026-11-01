defmodule Palee.Application.Channels.ChannelMargins do
  @moduledoc """
  The Palee team's view of Palee-managed messages (ADR-369), in the vendor
  console: Palee's margin per channel (a platform setting) and a box's
  monthly charge with the providers' cost beside it. The provider's cost
  is never shown to the box.
  """

  alias Palee.Application.Channels.SendThroughChannel
  alias Palee.Channels
  alias Palee.Organizations

  @doc "`%{margins_bps, updated_at}`."
  def show, do: Map.take(Channels.margins(), [:margins_bps, :updated_at])

  @doc "Saves margins (`%{\"sms\" => 2500}`): `{:ok, show}`."
  def save(params, actor_id) do
    margins = Map.get(params, :margins_bps, Map.get(params, "margins_bps"))

    with true <- is_map(margins) || {:error, {:invalid_fields, %{margins_bps: "invalid"}}},
         {:ok, saved} <- Channels.save_margins(margins, actor_id) do
      {:ok, Map.take(saved, [:margins_bps, :updated_at])}
    end
  end

  @doc """
  What Palee charges a box for a month's messages on Palee's account
  (`YYYY-MM` on the box's clock, this month when nil), for billing.
  """
  def monthly_charge(organization_id, month, now \\ DateTime.utc_now()) do
    with {:ok, organization_id} <- Ecto.UUID.cast(organization_id),
         %{} <- Organizations.get_by_id(organization_id) do
      context = %{organization_id: organization_id}
      env = SendThroughChannel.env(context, now)

      Channels.monthly_charge(context, month || current_month(now, env.time_zone), env)
    else
      _missing -> {:error, :not_found}
    end
  end

  defp current_month(now, zone) do
    local = DateTime.shift_zone!(now, zone)
    :io_lib.format("~4..0B-~2..0B", [local.year, local.month]) |> IO.iodata_to_binary()
  end
end

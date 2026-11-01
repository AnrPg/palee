defmodule Palee.Channels.PlatformSetting do
  @moduledoc """
  The installation's one Channels row (ADR-369): Palee's margin in basis
  points per channel on the messages it sends for a box. Platform data,
  edited by the Palee team only.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "channel_platform_settings" do
    field :singleton, :boolean, default: true
    field :margins_bps, :map, default: %{}
    field :updated_by_id, :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(setting, attrs) do
    setting
    |> cast(attrs, [:margins_bps, :updated_by_id])
    |> validate_required([:margins_bps])
    |> unique_constraint(:singleton)
  end
end

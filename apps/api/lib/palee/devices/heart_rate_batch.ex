defmodule Palee.Devices.HeartRateBatch do
  @moduledoc """
  Heart rate a watch recorded during an execution (ADR-375): `bpm` samples
  every `interval_ms`, the first at `started_offset_ms` of the execution's
  active time. Numbered per execution so a resend is stored once.
  """

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  schema "execution_heart_rate_batches" do
    field(:execution_id, :binary_id)
    field(:user_id, :binary_id)
    field(:platform, :string)
    field(:sequence, :integer)
    field(:started_offset_ms, :integer)
    field(:interval_ms, :integer)
    field(:bpm, {:array, :integer})

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end

defmodule Palee.Execution.ExecutionSplit do
  @moduledoc """
  One split mark of an execution (ADR-374): the end of a timed segment, or a
  round the athlete tapped, at `elapsed_ms` of active time since the start.
  """

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  schema "execution_splits" do
    field(:execution_id, :binary_id)
    field(:user_id, :binary_id)
    field(:segment_index, :integer)
    field(:section_id, :string)
    field(:section_ordinal, :integer)
    field(:phase, :string)
    field(:round, :integer, default: 0)
    field(:elapsed_ms, :integer)

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end

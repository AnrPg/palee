defmodule Palee.Devices.WatchOffer do
  @moduledoc """
  Whether the watch was offered for one execution (ADR-375 amendment,
  ANR's D8 rules): `asked` (with the person's `answer` once given) or
  `auto` (started on the watch without a question).
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Palee.Devices.Domain.WatchContract

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  schema "watch_offers" do
    field(:execution_id, :binary_id)
    field(:user_id, :binary_id)
    field(:platform, :string)
    field(:mode, :string)
    field(:answer, :string)

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(offer \\ %__MODULE__{}, attrs) do
    offer
    |> cast(attrs, [:execution_id, :user_id, :platform, :mode, :answer])
    |> validate_required([:execution_id, :user_id, :platform, :mode])
    |> validate_inclusion(:platform, WatchContract.platforms())
    |> validate_inclusion(:mode, ~w(asked auto))
    |> validate_inclusion(:answer, ~w(yes no))
    |> unique_constraint(:execution_id)
    |> check_constraint(:mode, name: :watch_offers_check)
  end
end

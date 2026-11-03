defmodule Palee.Devices.WatchLink do
  @moduledoc "A watch paired with the person's phone app (ADR-375): Apple Watch or Wear OS."

  use Ecto.Schema
  import Ecto.Changeset

  alias Palee.Devices.Domain.WatchContract

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  schema "watch_links" do
    field(:user_id, :binary_id)
    field(:platform, :string)
    field(:device_name, :string)
    field(:app_version, :string)
    field(:contract_version, :integer)
    field(:settings, :map, default: %{})
    field(:paired_at, :utc_datetime_usec)
    field(:last_seen_at, :utc_datetime_usec)

    timestamps(type: :utc_datetime_usec)
  end

  @fields ~w(user_id platform device_name app_version contract_version settings paired_at last_seen_at)a

  def changeset(link \\ %__MODULE__{}, attrs) do
    link
    |> cast(attrs, @fields)
    |> validate_required([:user_id, :platform, :contract_version, :paired_at, :last_seen_at])
    |> validate_inclusion(:platform, WatchContract.platforms())
    |> validate_length(:device_name, max: 60)
    |> validate_length(:app_version, max: 32)
    |> validate_number(:contract_version, greater_than_or_equal_to: 1)
    |> unique_constraint([:user_id, :platform])
    |> check_constraint(:platform, name: :watch_links_check)
  end
end

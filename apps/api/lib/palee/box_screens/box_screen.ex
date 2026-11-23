defmodule Palee.BoxScreens.BoxScreen do
  @moduledoc "A box screen (ADR-253): a TV on the box's wall, paired with a code."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "box_screens" do
    field :organization_id, :binary_id
    field :location_id, :binary_id
    field :name, :string
    field :pairing_code_hash, :binary
    field :pairing_code_expires_at, :utc_datetime_usec
    field :token_version, :integer, default: 0
    field :paired_at, :utc_datetime_usec
    field :last_seen_at, :utc_datetime_usec
    field :override_view, :string
    field :override_slot_id, :binary_id
    field :override_until, :utc_datetime_usec
    # ADR-746: the WOD a pin shows (nil = the class's «Τώρα») and one more
    # class sharing the screen this once.
    field :override_workout_id, :binary_id
    field :override_split_slot_id, :binary_id
    # ADR-746: the room the screen follows in automatic, and how it shows
    # classes that run together (`room` or `split`).
    field :space_id, :binary_id
    field :concurrent_mode, :string, default: "room"
    field :focus_changed_by_id, :binary_id
    field :focus_changed_at, :utc_datetime_usec
    field :created_by_id, :binary_id
    timestamps(type: :utc_datetime_usec)
  end

  @fields ~w(organization_id location_id name pairing_code_hash pairing_code_expires_at
             token_version paired_at last_seen_at override_view override_slot_id override_until
             override_workout_id override_split_slot_id space_id concurrent_mode
             focus_changed_by_id focus_changed_at created_by_id)a

  def changeset(screen \\ %__MODULE__{}, attrs) do
    screen
    |> cast(attrs, @fields)
    |> validate_required([:name])
    |> unique_constraint(:pairing_code_hash, name: :box_screens_pairing_code_hash_index)
    |> foreign_key_constraint(:location_id)
    |> foreign_key_constraint(:space_id, name: :box_screens_space_fkey)
    |> check_constraint(:concurrent_mode, name: :box_screens_concurrent_mode_check)
    |> check_constraint(:name, name: :box_screens_check)
  end
end

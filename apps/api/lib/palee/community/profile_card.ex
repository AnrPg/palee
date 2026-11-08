defmodule Palee.Community.ProfileCard do
  @moduledoc """
  ADR-554: what a person's profile shows besides name and avatar: «Λίγα
  λόγια» (`bio`) and the optional tabs they added, in their order. Readable
  by every signed-in session, written only by its owner (RLS).
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Palee.Community.Domain.ProfileTabs

  @primary_key {:user_id, :binary_id, autogenerate: false}

  schema "community_profile_cards" do
    field :bio, :string
    field :tabs, {:array, :string}, default: []
    field :box_id, :binary_id
    field :show_rank, :boolean, default: false

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(card \\ %__MODULE__{}, attrs) do
    card
    |> cast(attrs, [:user_id, :bio, :tabs, :box_id, :show_rank])
    |> validate_required([:user_id])
    |> validate_length(:bio, max: ProfileTabs.bio_max())
    |> validate_subset(:tabs, ProfileTabs.optional())
    |> foreign_key_constraint(:box_id)
  end
end

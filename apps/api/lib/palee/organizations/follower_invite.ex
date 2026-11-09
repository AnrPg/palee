defmodule Palee.Organizations.FollowerInvite do
  @moduledoc "ADR-580: a box's invitation to someone who follows it to become a box member."

  use Ecto.Schema
  import Ecto.Changeset

  alias Palee.Organizations.Domain.FollowerInvitePolicy

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "organization_follower_invites" do
    field :organization_id, :binary_id, read_after_writes: true
    field :user_id, :binary_id
    field :invited_by_id, :binary_id
    field :message, :string
    field :package_id, :binary_id
    field :offer_trial, :boolean, default: false
    field :status, :string, default: "sent"
    field :answered_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  def decline_changeset(invite, now) do
    invite
    |> change(status: "declined", answered_at: now)
    |> validate_inclusion(:status, FollowerInvitePolicy.statuses())
  end
end

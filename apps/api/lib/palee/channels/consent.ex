defmodule Palee.Channels.Consent do
  @moduledoc """
  A contact's consent to one channel for one purpose (ADR-350): when it
  was last granted and withdrawn, from where, and which consent text.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "channel_consents" do
    field :organization_id, :binary_id, read_after_writes: true
    field :contact_id, :binary_id
    field :channel, :string
    field :purpose, :string
    field :granted_at, :utc_datetime_usec
    field :withdrawn_at, :utc_datetime_usec
    field :source, :string
    field :text_version, :string
    field :recorded_by_id, :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(consent, attrs) do
    consent
    |> cast(attrs, [
      :contact_id,
      :channel,
      :purpose,
      :granted_at,
      :withdrawn_at,
      :source,
      :text_version,
      :recorded_by_id
    ])
    |> validate_required([:contact_id, :channel, :purpose, :source])
    |> unique_constraint([:contact_id, :channel, :purpose])
    |> check_constraint(:channel, name: :channel_consents_check)
  end
end

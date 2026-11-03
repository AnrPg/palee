defmodule Palee.Channels.MessageEvent do
  @moduledoc """
  Insert-only log of a message's attempts and delivery receipts (ADR-348
  §5). `event_key` deduplicates a receipt the provider sends twice.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "channel_message_events" do
    field :organization_id, :binary_id, read_after_writes: true
    field :message_id, :binary_id
    field :kind, :string
    field :status, :string
    field :provider_status, :string
    field :error_code, :string
    field :detail, :string
    field :event_key, :string
    field :occurred_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [
      :message_id,
      :kind,
      :status,
      :provider_status,
      :error_code,
      :detail,
      :event_key,
      :occurred_at
    ])
    |> validate_required([:message_id, :kind, :status, :occurred_at])
    |> unique_constraint([:organization_id, :event_key], name: :channel_message_events_key_index)
  end
end

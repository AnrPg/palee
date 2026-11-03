defmodule Palee.Channels.Contact do
  @moduledoc """
  A member's (`user_id`) or lead's (`lead_id`) mobile number in E.164 and
  language in one box (ADR-348 §4). `opted_out_at` is set by a STOP reply.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "channel_contacts" do
    field :organization_id, :binary_id, read_after_writes: true
    field :user_id, :binary_id
    field :lead_id, :binary_id
    field :phone_e164, :string
    field :locale, :string, default: "el"
    field :opted_out_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(contact, attrs) do
    contact
    |> cast(attrs, [:user_id, :lead_id, :phone_e164, :locale, :opted_out_at])
    |> validate_required([:phone_e164, :locale])
    |> unique_constraint([:organization_id, :user_id], name: :channel_contacts_user_index)
    |> unique_constraint([:organization_id, :lead_id], name: :channel_contacts_lead_index)
    |> check_constraint(:phone_e164, name: :channel_contacts_check)
  end
end

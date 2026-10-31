defmodule Palee.Integrations.MarketingConsent do
  @moduledoc """
  A member's yes (or later no) to the box's marketing email (ADR-380).
  The same columns as W3's channel consents (`granted_at`, `withdrawn_at`,
  `source`, `text_version`), so the two can be unified later.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  @fields ~w(user_id channel granted_at withdrawn_at source text_version)a

  schema "integration_marketing_consents" do
    field :organization_id, :binary_id, read_after_writes: true
    field :user_id, :binary_id
    field :channel, :string, default: "email"
    field :granted_at, :utc_datetime_usec
    field :withdrawn_at, :utc_datetime_usec
    field :source, :string
    field :text_version, :string
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(consent, attrs) do
    consent
    |> cast(attrs, @fields)
    |> validate_required([:user_id, :channel, :source, :text_version])
    |> unique_constraint([:organization_id, :user_id, :channel])
  end
end

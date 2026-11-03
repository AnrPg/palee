defmodule Palee.Channels.Connection do
  @moduledoc """
  A box's messaging provider (ADR-348 §2): its own account (`own`, with one
  of the vendors of ADR-396; the secrets encrypted at rest and never returned) or the Palee-managed one
  (`palee`, credentials in the platform config), the senders, the channels
  switched on, the monthly budget cap and quiet hours (ADR-349). Neither
  has a default (ADR-390): the box types its own cap when it turns a
  channel on, and quiet hours stay off until it opens them.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Palee.Infrastructure.Security.EncryptedBinary

  @primary_key {:id, :binary_id, autogenerate: true}

  @fields ~w(provider account_mode account_id secret webhook_secret base_url sms_sender viber_sender
             whatsapp_sender channels channel_order default_country monthly_budget_cents
             currency quiet_start_minute quiet_end_minute webhook_salt status error_code
             last_error checked_at updated_by_id)a

  schema "channel_connections" do
    field :organization_id, :binary_id, read_after_writes: true
    field :provider, :string
    field :account_mode, :string, default: "palee"
    field :account_id, :string
    field :secret, EncryptedBinary, redact: true
    # ADR-396: the vendor's own key for signing its reports (Vonage).
    field :webhook_secret, EncryptedBinary, redact: true
    field :base_url, :string
    field :sms_sender, :string
    field :viber_sender, :string
    field :whatsapp_sender, :string
    field :channels, {:array, :string}, default: []
    field :channel_order, {:array, :string}, default: ["sms", "viber", "whatsapp"]
    field :default_country, :string, default: "GR"
    field :monthly_budget_cents, :integer
    field :currency, :string, default: "EUR"
    field :quiet_start_minute, :integer
    field :quiet_end_minute, :integer
    field :webhook_salt, :binary, redact: true
    field :status, :string, default: "active"
    field :error_code, :string
    field :last_error, :string
    field :checked_at, :utc_datetime_usec
    field :updated_by_id, :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(connection, attrs) do
    connection
    |> cast(attrs, @fields)
    |> validate_required([:provider, :account_mode, :status, :default_country])
    |> unique_constraint(:organization_id)
    |> check_constraint(:provider, name: :channel_connections_check)
  end
end

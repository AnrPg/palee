defmodule Palee.Channels.EmailConnection do
  @moduledoc """
  A box's own email provider over SMTP (ADR-368): the host, port, TLS mode,
  user name and password (encrypted at rest, never returned, logged,
  journaled or exported), the sender and reply-to, whether it is switched on
  and the last «Δοκιμή σύνδεσης».
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Palee.Infrastructure.Security.EncryptedBinary

  @primary_key {:id, :binary_id, autogenerate: true}

  @fields ~w(host port tls_mode username secret from_address from_name reply_to enabled status
             error_code checked_at updated_by_id)a

  schema "channel_email_connections" do
    field :organization_id, :binary_id, read_after_writes: true
    field :host, :string
    field :port, :integer
    field :tls_mode, :string, default: "starttls"
    field :username, :string
    field :secret, EncryptedBinary, redact: true
    field :from_address, :string
    field :from_name, :string
    field :reply_to, :string
    field :enabled, :boolean, default: true
    field :status, :string, default: "unchecked"
    field :error_code, :string
    field :checked_at, :utc_datetime_usec
    field :updated_by_id, :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(connection, attrs) do
    connection
    |> cast(attrs, @fields)
    |> validate_required([:host, :port, :tls_mode, :username, :secret, :from_address, :status])
    |> unique_constraint(:organization_id)
    |> check_constraint(:status, name: :channel_email_connections_check)
  end
end

defmodule Palee.BoxSite.SiteDomain do
  @moduledoc "A custom host of a box's website (ADR-352 §5)."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  @fields ~w(host primary status verification_token attempts next_check_at checked_at
             verified_at active_at last_error created_by_id)a

  schema "box_site_domains" do
    field :organization_id, :binary_id, read_after_writes: true
    field :host, :string
    field :primary, :boolean, default: false
    field :status, :string, default: "pending_dns"
    field :verification_token, :string
    field :attempts, :integer, default: 0
    field :next_check_at, :utc_datetime_usec
    field :checked_at, :utc_datetime_usec
    field :verified_at, :utc_datetime_usec
    field :active_at, :utc_datetime_usec
    field :last_error, :string
    field :created_by_id, :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(domain, attrs) do
    domain
    |> cast(attrs, @fields)
    |> validate_required([:host, :status, :verification_token])
    |> unique_constraint(:host)
    |> unique_constraint(:primary, name: :box_site_domains_one_primary_index)
    |> check_constraint(:status, name: :box_site_domains_check)
  end
end

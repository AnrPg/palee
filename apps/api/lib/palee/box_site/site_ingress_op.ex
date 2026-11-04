defmodule Palee.BoxSite.SiteIngressOp do
  @moduledoc """
  ADR-398: one cluster call waiting to happen (apply or delete a custom
  host's Ingress), with its retries. Holds the host, so a delete outlives
  the domain row.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  @fields ~w(domain_id host action status attempts next_attempt_at claimed_at last_error)a

  schema "box_site_ingress_ops" do
    field :organization_id, :binary_id, read_after_writes: true
    field :domain_id, :binary_id
    field :host, :string
    field :action, :string
    field :status, :string, default: "pending"
    field :attempts, :integer, default: 0
    field :next_attempt_at, :utc_datetime_usec
    field :claimed_at, :utc_datetime_usec
    field :last_error, :string

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(op, attrs) do
    op
    |> cast(attrs, @fields)
    |> validate_required([:host, :action, :status, :next_attempt_at])
    |> validate_inclusion(:action, ["apply", "delete"])
    |> check_constraint(:status, name: :box_site_ingress_ops_check)
  end
end

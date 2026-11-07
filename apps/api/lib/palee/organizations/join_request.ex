defmodule Palee.Organizations.JoinRequest do
  @moduledoc "ADR-552: a person asking a box to take them in as a box member («Ζήτα να γίνεις μέλος»)."

  use Ecto.Schema
  import Ecto.Changeset

  alias Palee.Organizations.Domain.JoinRequestPolicy

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "organization_join_requests" do
    field :organization_id, :binary_id, read_after_writes: true
    field :user_id, :binary_id
    field :status, :string, default: "requested"
    field :decided_at, :utc_datetime_usec
    field :decided_by_id, :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  def create_changeset(params) do
    %__MODULE__{}
    |> cast(params, [:user_id])
    |> validate_required([:user_id])
    |> unique_constraint([:organization_id, :user_id],
      name: :organization_join_requests_one_open_index
    )
  end

  def close_changeset(request, params) do
    request
    |> cast(params, [:status, :decided_at, :decided_by_id])
    |> validate_required([:status, :decided_at])
    |> validate_inclusion(:status, JoinRequestPolicy.closed_statuses())
  end
end

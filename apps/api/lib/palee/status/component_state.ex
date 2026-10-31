defmodule Palee.Status.ComponentState do
  @moduledoc "ADR-364: the latest probe result of one status page component."

  use Ecto.Schema

  @primary_key {:component, :string, autogenerate: false}

  @type t :: %__MODULE__{}

  schema "status_component_states" do
    field :status, :string
    field :reason, :string
    field :checked_at, :utc_datetime_usec
    field :changed_at, :utc_datetime_usec
  end
end

defmodule Palee.Status.Subscriber do
  @moduledoc """
  ADR-364: an address that asked for status emails. Only the address, its
  digest (for the unique index), the language and the confirmation state.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  @type t :: %__MODULE__{}

  schema "status_subscribers" do
    field :email, :string
    field :email_digest, :string
    field :locale, :string, default: "en"
    field :confirm_token_digest, :string
    field :confirmed_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:email, :email_digest, :locale, :confirm_token_digest])
    |> validate_required([:email, :email_digest, :locale, :confirm_token_digest])
    |> unique_constraint(:email_digest)
  end

  def change_changeset(subscriber, attrs) do
    subscriber
    |> cast(attrs, [:locale, :confirm_token_digest, :confirmed_at])
    |> check_constraint(:confirmed_at, name: :status_subscribers_check)
  end
end

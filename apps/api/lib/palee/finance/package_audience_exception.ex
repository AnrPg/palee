defmodule Palee.Finance.PackageAudienceException do
  @moduledoc """
  ADR-553: one person a box always shows (`show`) or never shows (`hide`)
  its subscription packages to: one package, or every package when
  `membership_package_id` is nil.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Palee.Finance.Domain.PackageAudience

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "finance_package_audience_exceptions" do
    field :organization_id, :binary_id, read_after_writes: true
    field :membership_package_id, :binary_id
    field :user_id, :binary_id
    field :effect, :string
    field :created_by_id, :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(exception \\ %__MODULE__{}, params) do
    exception
    |> cast(params, [:membership_package_id, :user_id, :effect, :created_by_id])
    |> validate_required([:user_id, :effect])
    |> validate_inclusion(:effect, PackageAudience.effects())
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:membership_package_id)
    |> unique_constraint([:membership_package_id, :user_id],
      name: :finance_package_audience_exceptions_one_per_person_index
    )
  end
end

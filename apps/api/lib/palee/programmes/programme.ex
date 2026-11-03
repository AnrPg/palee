defmodule Palee.Programmes.Programme do
  @moduledoc """
  A training programme a box or a coach sells (ADR-370): what is shown
  and sold. The days themselves live in its published versions.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Palee.Programmes.Domain.ProgrammePolicy

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  @editable ~w(title summary description level goal equipment sessions_per_week price_cents
               currency listing preview_days refund_policy draft_weeks draft_days)a

  schema "programmes" do
    field :organization_id, :binary_id, read_after_writes: true
    field :author_id, :binary_id
    field :title, :string
    field :summary, :string
    field :description, :string
    field :level, :string, default: "all"
    field :goal, :string, default: "general"
    field :equipment, {:array, :string}, default: []
    field :sessions_per_week, :integer
    field :price_cents, :integer, default: 0
    field :currency, :string, default: "EUR"
    field :listing, :string, default: "box"
    field :status, :string, default: "draft"
    field :preview_days, :integer, default: 3
    field :refund_policy, :string, default: "before_start"
    field :draft_weeks, :integer, default: 4
    field :draft_days, {:array, :map}, default: []
    field :current_version_id, :binary_id
    field :published_at, :utc_datetime_usec
    field :archived_at, :utc_datetime_usec
    field :updated_by_id, :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  def editable_fields, do: @editable

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:organization_id, :author_id, :updated_by_id | @editable])
    |> validate_required([:title])
    |> validate()
  end

  def update_changeset(programme, attrs) do
    programme
    |> cast(attrs, [:updated_by_id | @editable])
    |> validate()
  end

  @doc "Lifecycle and version changes the domain already allowed."
  def state_changeset(programme, changes) do
    programme
    |> cast(changes, [
      :status,
      :current_version_id,
      :published_at,
      :archived_at,
      :updated_by_id
    ])
    |> validate_inclusion(:status, ProgrammePolicy.statuses())
    |> check_constraint(:status, name: :programmes_check)
  end

  defp validate(changeset) do
    changeset
    |> update_change(:title, &trim/1)
    |> update_change(:summary, &trim/1)
    |> validate_required([:title])
    |> validate_length(:title, min: 2, max: 120)
    |> validate_length(:summary, max: 600)
    |> validate_length(:description, max: 10_000)
    |> validate_inclusion(:level, ProgrammePolicy.levels())
    |> validate_inclusion(:goal, ProgrammePolicy.goals())
    |> validate_inclusion(:listing, ProgrammePolicy.listings())
    |> validate_inclusion(:refund_policy, ProgrammePolicy.refund_policies())
    |> validate_inclusion(:currency, ProgrammePolicy.currencies())
    |> validate_number(:price_cents,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: ProgrammePolicy.max_price_cents()
    )
    |> validate_number(:preview_days,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: ProgrammePolicy.max_preview_days()
    )
    |> validate_number(:sessions_per_week, greater_than_or_equal_to: 1, less_than_or_equal_to: 14)
    |> validate_length(:equipment, max: 30)
    |> validate_number(:draft_weeks,
      greater_than_or_equal_to: 1,
      less_than_or_equal_to: ProgrammePolicy.max_weeks()
    )
    |> check_constraint(:status, name: :programmes_check)
  end

  defp trim(value) when is_binary(value), do: String.trim(value)
  defp trim(value), do: value
end

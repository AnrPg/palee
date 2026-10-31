defmodule Palee.Leads.Lead do
  @moduledoc "ADR-344: a person interested in the box who is not a box member yet («Ενδιαφερόμενος»)."

  use Ecto.Schema
  import Ecto.Changeset

  alias Palee.Leads.Domain.Pipeline

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  schema "leads" do
    field :organization_id, :binary_id, read_after_writes: true
    field :name, :string
    field :email, :string
    field :phone, :string
    field :message, :string
    field :locale, :string
    field :stage, :string, default: "new"
    field :source, :string
    field :source_ref, :string
    field :campaign, :string
    field :interests, {:array, :string}, default: []
    field :owner_id, :binary_id
    field :user_id, :binary_id
    field :lost_reason, :string
    field :stage_changed_at, :utc_datetime_usec
    field :converted_at, :utc_datetime_usec
    field :last_contacted_at, :utc_datetime_usec
    field :consent_contact_at, :utc_datetime_usec
    field :consent_marketing_at, :utc_datetime_usec
    field :consent_text_version, :string
    field :consent_text_hash, :string
    field :marketing_opted_out_at, :utc_datetime_usec
    field :created_by_id, :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  @create_fields ~w(name email phone message locale stage source source_ref campaign interests
                    owner_id user_id stage_changed_at consent_contact_at consent_marketing_at
                    consent_text_version consent_text_hash created_by_id)a

  @update_fields ~w(name email phone message locale stage interests owner_id user_id lost_reason
                    stage_changed_at converted_at last_contacted_at consent_contact_at
                    consent_marketing_at consent_text_version consent_text_hash
                    marketing_opted_out_at campaign)a

  def create_changeset(params) do
    %__MODULE__{}
    |> cast(params, @create_fields)
    |> validate_required([:name, :source, :stage, :stage_changed_at])
    |> validate()
  end

  def update_changeset(lead, params) do
    lead
    |> cast(params, @update_fields)
    |> validate_required([:name, :stage, :stage_changed_at])
    |> validate()
  end

  defp validate(changeset) do
    changeset
    |> validate_inclusion(:stage, Pipeline.stages())
    |> validate_inclusion(:source, Pipeline.sources())
    |> validate_inclusion(:lost_reason, Pipeline.lost_reasons())
    |> validate_length(:name, min: 1, max: 120)
    |> check_constraint(:email, name: :leads_contact_check, message: "email_or_phone_required")
    |> unique_constraint(:email,
      name: :leads_one_open_per_email_index,
      message: "already_open"
    )
    |> unique_constraint(:source_ref, name: :leads_source_ref_index)
  end
end

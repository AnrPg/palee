defmodule Palee.BoxSite.SiteSubmission do
  @moduledoc """
  A website form submission on its way to the leads context (ADR-353), and
  its optional Conversions API event (ADR-354 §5). Personal fields are
  cleared once delivered.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  @fields ~w(kind name email phone message preferred_time class_type_id locale marketing_opt_in
             visitor_id attribution consent_text_version consent_text_hash submitted_at status
             attempts next_attempt_at claimed_at lead_id delivered_at last_error redacted_at
             conversion_status conversion_payload conversion_attempts conversion_next_at
             conversion_claimed_at)a

  schema "box_site_submissions" do
    field :organization_id, :binary_id, read_after_writes: true
    field :kind, :string
    field :name, :string
    field :email, :string
    field :phone, :string
    field :message, :string
    field :preferred_time, :string
    field :class_type_id, :binary_id
    field :locale, :string, default: "el"
    field :marketing_opt_in, :boolean, default: false
    field :visitor_id, :binary_id
    field :attribution, :map, default: %{}
    field :consent_text_version, :string
    field :consent_text_hash, :string
    field :submitted_at, :utc_datetime_usec
    field :status, :string, default: "pending"
    field :attempts, :integer, default: 0
    field :next_attempt_at, :utc_datetime_usec
    field :claimed_at, :utc_datetime_usec
    field :lead_id, :binary_id
    field :delivered_at, :utc_datetime_usec
    field :last_error, :string
    field :redacted_at, :utc_datetime_usec
    field :conversion_status, :string, default: "none"
    field :conversion_payload, :map
    field :conversion_attempts, :integer, default: 0
    field :conversion_next_at, :utc_datetime_usec
    field :conversion_claimed_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(submission, attrs) do
    submission
    |> cast(attrs, @fields)
    |> validate_required([:kind, :submitted_at, :status])
    |> check_constraint(:status, name: :box_site_submissions_check)
  end
end

defmodule Palee.BoxSite.SiteConsent do
  @moduledoc "One row of a box website's consent log (ADR-354 §4); insert-only."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  @fields ~w(visitor_id banner_version analytics marketing action recorded_at expires_at)a

  schema "box_site_consents" do
    field :organization_id, :binary_id, read_after_writes: true
    field :visitor_id, :binary_id
    field :banner_version, :integer
    field :analytics, :boolean
    field :marketing, :boolean
    field :action, :string
    field :recorded_at, :utc_datetime_usec
    field :expires_at, :utc_datetime_usec
  end

  def changeset(consent, attrs) do
    consent
    |> cast(attrs, @fields)
    |> validate_required(@fields)
    |> check_constraint(:action, name: :box_site_consents_check)
  end
end

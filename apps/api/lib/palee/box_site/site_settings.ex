defmodule Palee.BoxSite.SiteSettings do
  @moduledoc """
  A box's website settings (ADR-352, ADR-354). `conversions_api_token` is
  encrypted at rest and never returned by the API.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Palee.Infrastructure.Security.EncryptedBinary

  @primary_key {:id, :binary_id, autogenerate: true}

  @fields ~w(section_order hidden_sections public_schedule public_wod faq translation_locales visible_locales forms_enabled meta_pixel_id
             ga4_measurement_id gtm_container_id banner_version conversions_api_enabled
             conversions_api_token updated_by_id)a

  schema "box_site_settings" do
    field :organization_id, :binary_id, read_after_writes: true
    field :section_order, {:array, :string}, default: []
    field :hidden_sections, {:array, :string}, default: []
    field :public_schedule, :boolean, default: false
    field :public_wod, :boolean, default: false
    field :translation_locales, {:array, :string}, default: ["en"]
    field :visible_locales, {:array, :string}, default: ["en"]
    field :faq, :map, default: %{"entries" => []}
    field :forms_enabled, :boolean, default: true
    field :meta_pixel_id, :string
    field :ga4_measurement_id, :string
    field :gtm_container_id, :string
    field :banner_version, :integer, default: 1
    field :conversions_api_enabled, :boolean, default: false
    field :conversions_api_token, EncryptedBinary, redact: true
    field :lock_version, :integer, default: 1
    field :updated_by_id, :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(settings, attrs) do
    settings
    |> cast(attrs, @fields)
    |> then(
      &if(&1.data.__meta__.state == :loaded, do: optimistic_lock(&1, :lock_version), else: &1)
    )
    |> check_constraint(:meta_pixel_id, name: :box_site_settings_check)
    |> check_constraint(:visible_locales, name: :box_site_settings_locales_check)
    |> unique_constraint(:organization_id)
  end
end

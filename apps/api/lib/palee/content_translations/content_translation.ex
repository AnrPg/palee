defmodule Palee.ContentTranslations.ContentTranslation do
  @moduledoc "One translated text of a business, in one language (ADR-500)."

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "content_translations" do
    field :organization_id, :binary_id
    field :subject_kind, :string
    field :subject_id, :binary_id
    field :field, :string
    field :locale, :string
    field :text, :string
    field :source_hash, :string
    field :origin, :string
    field :reviewed_at, :utc_datetime_usec
    field :updated_by_id, :binary_id

    timestamps(type: :utc_datetime_usec)
  end
end

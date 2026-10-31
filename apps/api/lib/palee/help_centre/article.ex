defmodule Palee.HelpCentre.Article do
  @moduledoc "One help article in one locale (ADR-362). Platform content, no tenant."

  use Ecto.Schema
  import Ecto.Changeset

  alias Palee.HelpCentre.Domain.ArticlePolicy

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "help_articles" do
    field :slug, :string
    field :locale, :string
    field :title, :string
    field :summary, :string
    field :body, :string, default: ""
    field :audience, :string, default: "staff"
    field :feature_key, :string
    field :guide_id, :string
    field :screens, {:array, :string}, default: []
    field :keywords, {:array, :string}, default: []
    field :status, :string, default: "draft"
    field :source, :string, default: "palee"
    field :complete, :boolean, default: true
    field :version, :integer, default: 1
    field :position, :integer, default: 100
    field :updated_by_id, :binary_id
    field :published_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  @fields [
    :slug,
    :locale,
    :title,
    :summary,
    :body,
    :audience,
    :feature_key,
    :guide_id,
    :screens,
    :keywords,
    :status,
    :source,
    :complete,
    :version,
    :position,
    :updated_by_id,
    :published_at
  ]

  def changeset(article, attrs) do
    article
    |> cast(attrs, @fields)
    |> validate_required([:slug, :locale, :title, :summary, :status, :source, :audience])
    |> validate_inclusion(:locale, ArticlePolicy.locales())
    |> validate_inclusion(:status, ArticlePolicy.statuses())
    |> validate_inclusion(:audience, ArticlePolicy.audiences())
    |> validate_length(:title, max: 160)
    |> validate_length(:summary, max: 500)
    |> validate_length(:body, max: 20_000)
    |> unique_constraint([:slug, :locale])
    |> check_constraint(:slug, name: :help_articles_check)
  end
end

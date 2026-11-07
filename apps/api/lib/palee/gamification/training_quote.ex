defmodule Palee.Gamification.TrainingQuote do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "training_quotes" do
    field :body, :string
    field :author, :string
    field :locale, :string, default: "en"

    timestamps()
  end

  def changeset(quote, attrs) do
    quote
    |> cast(attrs, [:body, :author, :locale])
    |> validate_required([:body])
  end
end

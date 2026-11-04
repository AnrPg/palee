defmodule PaleeWeb.Schemas.ExerciseSuggestions do
  @moduledoc "OpenAPI schemas of exercise-name suggestions (ADR-461)."

  alias OpenApiSpex.{Parameter, Schema}

  def parameters do
    [
      %Parameter{
        name: :q,
        in: :query,
        required: false,
        description: "What the person typed so far (up to 80 characters are used)",
        schema: %Schema{type: :string}
      },
      %Parameter{
        name: :organization_id,
        in: :query,
        required: false,
        description:
          "The box whose WOD names to include; ignored unless the person belongs to it",
        schema: %Schema{type: :string, format: :uuid}
      },
      %Parameter{
        name: :limit,
        in: :query,
        required: false,
        description: "Suggestions per group, 1 to 10 (default 5)",
        schema: %Schema{type: :integer, minimum: 1, maximum: 10}
      }
    ]
  end

  def item do
    %Schema{
      title: "ExerciseSuggestion",
      type: :object,
      properties: %{
        name: %Schema{type: :string, description: "The name to put in the field"},
        catalog_slug: %Schema{
          type: :string,
          nullable: true,
          description: "The Palee catalog entry the name links to, if any"
        },
        hint: %Schema{
          type: :string,
          nullable: true,
          description:
            "For a palee item, the catalog category (strength, bodyweight, cardio, mobility, skill)"
        },
        uses_count: %Schema{
          type: :integer,
          description: "How often the person (mine) or the box (box) used the name; 0 for palee"
        }
      },
      required: [:name, :catalog_slug, :hint, :uses_count]
    }
  end

  def group do
    %Schema{
      title: "ExerciseSuggestionGroup",
      type: :object,
      properties: %{
        source: %Schema{type: :string, enum: ["mine", "box", "palee"]},
        items: %Schema{type: :array, items: item()}
      },
      required: [:source, :items]
    }
  end

  def response do
    %Schema{
      title: "ExerciseSuggestionsResponse",
      type: :object,
      description:
        "Groups in order mine, box, palee; a name appears once; empty groups are left out",
      properties: %{groups: %Schema{type: :array, items: group()}},
      required: [:groups]
    }
  end
end

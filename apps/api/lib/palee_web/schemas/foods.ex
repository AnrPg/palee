defmodule PaleeWeb.Schemas.Foods do
  @moduledoc "OpenAPI schemas of barcode foods and the person's own foods (ADR-376)."

  alias OpenApiSpex.Schema
  alias PaleeWeb.Schemas.Community

  @maybe_string %Schema{type: :string, nullable: true}
  @portion %Schema{type: :string, enum: ~w(protein carbs veg fat), nullable: true}

  def body(schema), do: Community.body(schema)
  def error, do: %Schema{type: :object, additionalProperties: true}

  def nutrients do
    %Schema{
      title: "FoodNutrients",
      type: :object,
      nullable: true,
      description:
        "Grams per 100 g. Only when a coach's plan sets macros and macros are not hidden; never energy",
      properties: %{
        proteins: %Schema{type: :number},
        carbohydrates: %Schema{type: :number},
        fat: %Schema{type: :number},
        fiber: %Schema{type: :number},
        sugars: %Schema{type: :number},
        salt: %Schema{type: :number}
      }
    }
  end

  def food do
    %Schema{
      title: "Food",
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid, nullable: true, description: "Own foods only"},
        barcode: @maybe_string,
        name: %Schema{type: :string},
        brand: @maybe_string,
        quantity: @maybe_string,
        serving_size: @maybe_string,
        image_url: @maybe_string,
        portion_hint: @portion,
        note: @maybe_string,
        nutrients: nutrients()
      },
      required: [:name, :nutrients, :portion_hint]
    }
  end

  def attribution do
    %Schema{
      title: "FoodAttribution",
      type: :object,
      nullable: true,
      description: "Shown with every Open Food Facts product (ODbL 1.0)",
      properties: %{
        source: %Schema{type: :string},
        licence: %Schema{type: :string},
        licence_url: %Schema{type: :string},
        images_licence: %Schema{type: :string},
        url: %Schema{type: :string}
      },
      required: [:images_licence, :licence, :licence_url, :source, :url]
    }
  end

  def barcode_response do
    %Schema{
      title: "BarcodeLookup",
      type: :object,
      properties: %{
        barcode: %Schema{type: :string},
        status: %Schema{
          type: :string,
          enum: ~w(found pending manual),
          description:
            "`pending`: still asking, scan again in a few seconds; `manual`: write it down yourself"
        },
        source: %Schema{type: :string, enum: ~w(open_food_facts custom), nullable: true},
        reason: %Schema{
          type: :string,
          nullable: true,
          enum: ~w(not_found failed in_store_code),
          description: "Why the manual entry"
        },
        food: %Schema{allOf: [food()], nullable: true},
        macros_visible: %Schema{type: :boolean},
        attribution: attribution()
      },
      required: [:barcode, :macros_visible, :status]
    }
  end

  def custom_food_request do
    %Schema{
      title: "CustomFoodRequest",
      type: :object,
      properties: %{
        name: %Schema{type: :string, minLength: 1, maxLength: 120},
        barcode: %Schema{type: :string, nullable: true},
        brand: %Schema{type: :string, nullable: true, maxLength: 120},
        serving_label: %Schema{type: :string, nullable: true, maxLength: 60},
        note: %Schema{type: :string, nullable: true, maxLength: 280},
        portion_hint: @portion,
        nutrients: %Schema{
          type: :object,
          nullable: true,
          additionalProperties: %Schema{type: :number, minimum: 0, maximum: 100}
        }
      }
    }
  end

  def custom_food_create_request do
    %Schema{custom_food_request() | title: "CustomFoodCreateRequest", required: [:name]}
  end

  def food_response do
    %Schema{title: "FoodResponse", type: :object, properties: %{food: food()}, required: [:food]}
  end

  def foods_response do
    %Schema{
      title: "CustomFoodsResponse",
      type: :object,
      properties: %{
        foods: %Schema{type: :array, items: food()},
        macros_visible: %Schema{type: :boolean}
      },
      required: [:foods, :macros_visible]
    }
  end
end

defmodule PaleeWeb.Schemas.Foods do
  @moduledoc "OpenAPI schemas of barcode foods and the person's own foods (ADR-376)."

  alias OpenApiSpex.{MediaType, RequestBody, Schema}
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
        shared_at: %Schema{
          type: :string,
          format: :"date-time",
          nullable: true,
          description:
            "Own foods only: when the person shared the product with everyone (ADR-421 addendum)"
        },
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
      description:
        "Shown with every product from a public source: Open Food Facts (ODbL 1.0), " <>
          "USDA FoodData Central (CC0), a licensed product list (its own licence) or " <>
          "Palee members (ODbL 1.0)",
      properties: %{
        source: %Schema{type: :string},
        licence: %Schema{type: :string},
        licence_url: @maybe_string,
        images_licence: @maybe_string,
        url: @maybe_string
      },
      required: [:licence, :source]
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
        source: %Schema{
          type: :string,
          enum: ~w(open_food_facts usda_fdc catalogue palee_members custom),
          nullable: true,
          description: "`palee_members`: a product members shared (ADR-421 addendum)"
        },
        reason: %Schema{
          type: :string,
          nullable: true,
          enum: ~w(not_found failed in_store_code),
          description: "Why the manual entry"
        },
        food: %Schema{allOf: [food()], nullable: true},
        macros_visible: %Schema{type: :boolean},
        label_reading: %Schema{
          type: :boolean,
          description: "Whether «Φωτογραφία ετικέτας» can prefill the manual entry (ADR-421)"
        },
        attribution: attribution()
      },
      required: [:barcode, :macros_visible, :status]
    }
  end

  def label_read_body do
    %RequestBody{
      required: true,
      content: %{
        "multipart/form-data" => %MediaType{
          schema: %Schema{
            type: :object,
            properties: %{
              front: %Schema{type: :string, format: :binary, description: "The front of the pack"},
              nutrition: %Schema{
                type: :string,
                format: :binary,
                description: "The nutrition table"
              },
              locale: %Schema{type: :string, maxLength: 10}
            }
          }
        }
      }
    }
  end

  def label_read_response do
    %Schema{
      title: "FoodLabelReading",
      type: :object,
      properties: %{
        food: %Schema{
          type: :object,
          properties: %{
            name: @maybe_string,
            brand: @maybe_string,
            serving_label: @maybe_string,
            portion_hint: @portion,
            nutrients: nutrients()
          },
          required: [:name, :brand, :serving_label, :portion_hint, :nutrients]
        },
        macros_visible: %Schema{type: :boolean}
      },
      required: [:food, :macros_visible]
    }
  end

  def barcode_misses_response do
    %Schema{
      title: "BarcodeMisses",
      type: :object,
      properties: %{
        misses: %Schema{
          type: :array,
          items: %Schema{
            type: :object,
            properties: %{
              barcode: %Schema{type: :string},
              country: %Schema{type: :string, description: "ISO 3166 alpha-2; empty when unknown"},
              scans: %Schema{type: :integer},
              first_seen_on: %Schema{type: :string, format: :date},
              last_seen_on: %Schema{type: :string, format: :date}
            },
            required: [:barcode, :country, :scans, :first_seen_on, :last_seen_on]
          }
        }
      },
      required: [:misses]
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
        },
        share: %Schema{
          type: :boolean,
          description:
            "«Μοιράσου το» (ADR-421 addendum): share the product (barcode, name, brand, " <>
              "portion, nutrition per 100 g; nothing about the person) with all Palee members " <>
              "and Open Food Facts. Only for a product barcode; never by default"
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

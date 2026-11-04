defmodule PaleeWeb.Schemas.AthleteUse do
  @moduledoc "OpenAPI schemas of whether a profile also trains with Palee (ADR-463)."

  alias OpenApiSpex.{MediaType, RequestBody, Schema}

  def trains_with_palee do
    %Schema{
      type: :boolean,
      nullable: true,
      description:
        "ADR-463: staff's answer to «do you train with Palee too?»; null = never asked, read as true"
    }
  end

  def body do
    %RequestBody{
      required: true,
      content: %{
        "application/json" => %MediaType{
          schema: %Schema{
            title: "TrainsWithPaleeUpdate",
            type: :object,
            properties: %{trains_with_palee: %Schema{type: :boolean}},
            required: [:trains_with_palee]
          }
        }
      }
    }
  end

  def response do
    %Schema{
      title: "TrainsWithPaleeResponse",
      type: :object,
      properties: %{trains_with_palee: %Schema{type: :boolean}},
      required: [:trains_with_palee]
    }
  end
end

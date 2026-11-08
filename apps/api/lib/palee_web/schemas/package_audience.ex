defmodule PaleeWeb.Schemas.PackageAudience do
  @moduledoc "ADR-553: «Ποιος βλέπει τα πακέτα» payloads."

  alias OpenApiSpex.Schema

  @audiences ~w(all own none)
  @effects ~w(show hide)

  def person do
    %Schema{
      title: "PackageAudiencePerson",
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        nickname: %Schema{type: :string, nullable: true},
        handle: %Schema{type: :string, nullable: true},
        avatar_url: %Schema{type: :string, nullable: true}
      },
      required: [:avatar_url, :handle, :id, :nickname]
    }
  end

  def exception do
    %Schema{
      title: "PackageAudienceException",
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        package_id: %Schema{
          type: :string,
          format: :uuid,
          nullable: true,
          description: "The package; null for every package of the box"
        },
        effect: %Schema{type: :string, enum: @effects},
        person: person()
      },
      required: [:effect, :id, :package_id, :person]
    }
  end

  def settings do
    %Schema{
      title: "PackageAudienceSettings",
      type: :object,
      properties: %{
        audience: %Schema{type: :string, enum: @audiences},
        exceptions: %Schema{type: :array, items: exception()}
      },
      required: [:audience, :exceptions]
    }
  end

  def box_request do
    %Schema{
      title: "PackageAudienceBoxRequest",
      type: :object,
      properties: %{audience: %Schema{type: :string, enum: @audiences}},
      required: [:audience]
    }
  end

  def package_request do
    %Schema{
      title: "PackageAudiencePackageRequest",
      type: :object,
      properties: %{
        audience: %Schema{
          type: :string,
          enum: @audiences,
          nullable: true,
          description: "null: follows the box"
        }
      },
      required: [:audience]
    }
  end

  def package_response do
    %Schema{
      title: "PackageAudiencePackageResponse",
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        audience: %Schema{type: :string, enum: @audiences, nullable: true}
      },
      required: [:audience, :id]
    }
  end

  def exception_request do
    %Schema{
      title: "PackageAudienceExceptionRequest",
      type: :object,
      properties: %{
        user_id: %Schema{type: :string, format: :uuid},
        package_id: %Schema{type: :string, format: :uuid, nullable: true},
        effect: %Schema{type: :string, enum: @effects}
      },
      required: [:effect, :user_id]
    }
  end
end

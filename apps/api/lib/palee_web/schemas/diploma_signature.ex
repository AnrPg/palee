defmodule PaleeWeb.Schemas.DiplomaSignature do
  @moduledoc "OpenAPI schemas of a coach's diploma signature (ADR-377 addendum)."

  alias OpenApiSpex.Schema

  def signature do
    %Schema{
      title: "DiplomaSignature",
      type: :object,
      nullable: true,
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        content_type: %Schema{type: :string, enum: ["image/png", "image/jpeg"]},
        byte_size: %Schema{type: :integer},
        width: %Schema{type: :integer},
        height: %Schema{type: :integer},
        updated_at: %Schema{type: :string, format: :"date-time"}
      },
      required: [:id, :content_type, :byte_size, :width, :height, :updated_at]
    }
  end

  def limits do
    %Schema{
      title: "DiplomaSignatureLimits",
      type: :object,
      properties: %{
        max_bytes: %Schema{type: :integer},
        content_types: %Schema{type: :array, items: %Schema{type: :string}},
        min_width: %Schema{type: :integer},
        min_height: %Schema{type: :integer},
        max_width: %Schema{type: :integer},
        max_height: %Schema{type: :integer}
      },
      required: [:max_bytes, :content_types, :min_width, :min_height, :max_width, :max_height]
    }
  end

  def show_response do
    %Schema{
      title: "DiplomaSignatureResponse",
      type: :object,
      properties: %{
        eligible: %Schema{
          type: :boolean,
          description: "Whether the person awards ranks somewhere (owner, admin or coach)"
        },
        signature: signature(),
        limits: limits()
      },
      required: [:eligible, :signature, :limits]
    }
  end

  def upload_request do
    %Schema{
      title: "DiplomaSignatureUpload",
      type: :object,
      properties: %{
        image_base64: %Schema{
          type: :string,
          description: "The PNG or JPEG file, base64 (a data: URL prefix is accepted)"
        }
      },
      required: [:image_base64]
    }
  end

  def upload_response do
    %Schema{
      title: "DiplomaSignatureUploadResponse",
      type: :object,
      properties: %{signature: signature()},
      required: [:signature]
    }
  end

  def image, do: %Schema{type: :string, format: :binary}
  def error, do: %Schema{type: :object, additionalProperties: true}
end

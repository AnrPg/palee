defmodule PaleeWeb.Schemas.JoinRequests do
  @moduledoc "ADR-552: «Ζήτα να γίνεις μέλος» payloads."

  alias OpenApiSpex.Schema

  @statuses ~w(requested accepted declined cancelled)

  def mine do
    %Schema{
      title: "MyJoinRequest",
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        status: %Schema{type: :string, enum: @statuses},
        requested_at: %Schema{type: :string, format: :"date-time"},
        decided_at: %Schema{type: :string, format: :"date-time", nullable: true},
        box: %Schema{
          type: :object,
          properties: %{slug: %Schema{type: :string}, name: %Schema{type: :string}},
          required: [:name, :slug]
        }
      },
      required: [:box, :decided_at, :id, :requested_at, :status]
    }
  end

  def mine_response do
    %Schema{
      title: "MyJoinRequestResponse",
      type: :object,
      properties: %{request: %Schema{allOf: [mine()], nullable: true}},
      required: [:request]
    }
  end

  def staff do
    %Schema{
      title: "StaffJoinRequest",
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        status: %Schema{type: :string, enum: @statuses},
        requested_at: %Schema{type: :string, format: :"date-time"},
        decided_at: %Schema{type: :string, format: :"date-time", nullable: true},
        person: %Schema{
          type: :object,
          nullable: true,
          properties: %{
            id: %Schema{type: :string, format: :uuid},
            nickname: %Schema{type: :string},
            handle: %Schema{type: :string, nullable: true},
            avatar_url: %Schema{type: :string, nullable: true}
          },
          required: [:avatar_url, :handle, :id, :nickname]
        }
      },
      required: [:decided_at, :id, :person, :requested_at, :status]
    }
  end

  def staff_list do
    %Schema{
      title: "StaffJoinRequestList",
      type: :object,
      properties: %{requests: %Schema{type: :array, items: staff()}},
      required: [:requests]
    }
  end

  def staff_response do
    %Schema{
      title: "StaffJoinRequestResponse",
      type: :object,
      properties: %{request: staff()},
      required: [:request]
    }
  end
end

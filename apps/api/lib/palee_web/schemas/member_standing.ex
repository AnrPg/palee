defmodule PaleeWeb.Schemas.MemberStanding do
  @moduledoc "OpenAPI shape of a member's standing (ADR-595), the same for the member and the staff."

  alias OpenApiSpex.Schema

  @statuses ~w(active trial comped unpaid overdue leaving expiring paused expired cancelled former no_package)

  def schema do
    %Schema{
      title: "MemberStanding",
      type: :object,
      nullable: true,
      description:
        "ADR-595: the status and the line under it, worked out once and shown alike to the member and the staff",
      required: [
        :access_until,
        :benefit,
        :grace_until,
        :outstanding_cents,
        :status,
        :unpaid_since
      ],
      properties: %{
        status: %Schema{type: :string, enum: @statuses},
        grace_until: %Schema{
          type: :string,
          format: :date,
          nullable: true,
          description: "The last day of the grace the member is in"
        },
        benefit: %Schema{
          type: :string,
          enum: ["grace", "free_access"],
          nullable: true,
          description:
            "ADR-612: a grace or free access the box gave; it lasts through `grace_until`"
        },
        access_until: %Schema{
          type: :string,
          format: :date,
          nullable: true,
          description: "Leaving or former: the last day of the package they kept"
        },
        outstanding_cents: %Schema{type: :integer, minimum: 0},
        unpaid_since: %Schema{
          type: :string,
          format: :date,
          nullable: true,
          description: "The due date of the oldest charge still open"
        }
      }
    }
  end
end

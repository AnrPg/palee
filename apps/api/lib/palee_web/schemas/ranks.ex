defmodule PaleeWeb.Schemas.Ranks do
  @moduledoc "OpenAPI schemas of belts and levels (ADR-377)."

  alias OpenApiSpex.Schema
  alias PaleeWeb.Schemas.Community

  @uuid %Schema{type: :string, format: :uuid}
  @maybe_string %Schema{type: :string, nullable: true}
  @maybe_integer %Schema{type: :integer, nullable: true}
  @color %Schema{
    type: :string,
    nullable: true,
    enum: ~w(white grey yellow orange green blue purple brown red black pink),
    description: "Belt palette key; the screen maps it to the theme's --belt-* token"
  }

  def body(schema), do: Community.body(schema)
  def error, do: %Schema{type: :object, additionalProperties: true}

  def requirements do
    %Schema{
      title: "RankRequirements",
      type: :object,
      properties: %{
        min_classes: %Schema{type: :integer, minimum: 0, maximum: 2000},
        min_days: %Schema{type: :integer, minimum: 0, maximum: 3650},
        skills: %Schema{type: :array, maxItems: 20, items: %Schema{type: :string, maxLength: 120}}
      }
    }
  end

  def rank do
    %Schema{
      title: "Rank",
      type: :object,
      properties: %{
        id: @uuid,
        position: %Schema{type: :integer},
        name: %Schema{type: :string},
        color: @color,
        max_stripes: %Schema{type: :integer},
        requirements: requirements(),
        scale_level_slug: @maybe_string
      },
      required: [:id, :max_stripes, :name, :position, :requirements]
    }
  end

  def ladder do
    %Schema{
      title: "RankLadder",
      type: :object,
      properties: %{
        id: @uuid,
        name: %Schema{type: :string},
        discipline: %Schema{type: :string, description: "A workout type (ADR-275)"},
        family: @maybe_string,
        style: %Schema{type: :string, enum: ~w(belt level)},
        class_type_ids: %Schema{type: :array, items: @uuid},
        ranks: %Schema{type: :array, items: rank()}
      },
      required: [:class_type_ids, :discipline, :id, :name, :ranks, :style]
    }
  end

  def rank_input do
    %Schema{
      title: "RankInput",
      type: :object,
      properties: %{
        id: %Schema{
          type: :string,
          format: :uuid,
          nullable: true,
          description: "Keep an existing rank"
        },
        name: %Schema{type: :string, maxLength: 60},
        color: @color,
        max_stripes: %Schema{type: :integer, minimum: 0, maximum: 10},
        requirements: requirements(),
        scale_level_slug: @maybe_string
      },
      required: [:name]
    }
  end

  def ladder_request do
    %Schema{
      title: "RankLadderRequest",
      type: :object,
      properties: %{
        template: %Schema{
          type: :string,
          description: "Start from a template («Πρότυπα»); fields sent override it"
        },
        name: %Schema{type: :string, maxLength: 60},
        discipline: %Schema{type: :string},
        style: %Schema{type: :string, enum: ~w(belt level)},
        class_type_ids: %Schema{type: :array, maxItems: 20, items: @uuid},
        position: %Schema{type: :integer, minimum: 0},
        ranks: %Schema{type: :array, minItems: 1, maxItems: 30, items: rank_input()}
      }
    }
  end

  def ladder_response do
    %Schema{
      title: "RankLadderResponse",
      type: :object,
      properties: %{ladder: ladder()},
      required: [:ladder]
    }
  end

  def ladders_response do
    %Schema{
      title: "RankLaddersResponse",
      type: :object,
      properties: %{
        ladders: %Schema{type: :array, items: ladder()},
        templates: %Schema{
          type: :array,
          items: %Schema{type: :object, additionalProperties: true}
        },
        colors: %Schema{type: :array, items: %Schema{type: :string}}
      },
      required: [:colors, :ladders, :templates]
    }
  end

  def award do
    %Schema{
      title: "RankAward",
      type: :object,
      properties: %{
        id: @uuid,
        ladder_id: @uuid,
        rank_id: @uuid,
        rank_name: @maybe_string,
        color: @color,
        stripes: %Schema{type: :integer},
        awarded_on: %Schema{type: :string, format: :date},
        note: @maybe_string,
        skills_checked: %Schema{type: :array, items: %Schema{type: :string}},
        certificate_number: %Schema{type: :string},
        revoked: %Schema{type: :boolean},
        revoke_reason: @maybe_string
      },
      required: [
        :awarded_on,
        :certificate_number,
        :id,
        :ladder_id,
        :rank_id,
        :revoked,
        :skills_checked,
        :stripes
      ]
    }
  end

  def standing do
    count = %Schema{
      type: :object,
      properties: %{done: @maybe_integer, needed: @maybe_integer},
      required: [:done, :needed]
    }

    %Schema{
      title: "RankStanding",
      type: :object,
      properties: %{
        ladder: ladder(),
        current: %Schema{
          type: :object,
          nullable: true,
          properties: %{
            award_id: @uuid,
            rank: rank(),
            stripes: %Schema{type: :integer},
            awarded_on: %Schema{type: :string, format: :date}
          },
          required: [:award_id, :awarded_on, :rank, :stripes]
        },
        next: %Schema{allOf: [rank()], nullable: true},
        progress: %Schema{
          type: :object,
          nullable: true,
          description:
            "Towards the next rank; `ready` only says the counted requirements are met",
          properties: %{
            rank_id: @uuid,
            classes: count,
            days: count,
            skills: %Schema{type: :array, items: %Schema{type: :string}},
            ready: %Schema{type: :boolean}
          },
          required: [:classes, :days, :rank_id, :ready, :skills]
        },
        history: %Schema{type: :array, items: award()}
      },
      required: [:current, :history, :ladder, :next, :progress]
    }
  end

  def standings_response do
    %Schema{
      title: "RankStandingsResponse",
      type: :object,
      properties: %{
        user_id: @uuid,
        ladders: %Schema{type: :array, items: standing()}
      },
      required: [:ladders]
    }
  end

  def award_request do
    %Schema{
      title: "RankAwardRequest",
      type: :object,
      properties: %{
        ladder_id: @uuid,
        rank_id: @uuid,
        stripes: %Schema{type: :integer, minimum: 0, maximum: 10},
        awarded_on: %Schema{type: :string, format: :date},
        note: %Schema{type: :string, maxLength: 500},
        skills_checked: %Schema{type: :array, maxItems: 30, items: %Schema{type: :string}}
      },
      required: [:ladder_id, :rank_id]
    }
  end

  def revoke_request do
    %Schema{
      title: "RankAwardRevokeRequest",
      type: :object,
      properties: %{reason: %Schema{type: :string, minLength: 2, maxLength: 280}},
      required: [:reason]
    }
  end

  def award_response do
    %Schema{
      title: "RankAwardResponse",
      type: :object,
      properties: %{award: award()},
      required: [:award]
    }
  end

  def pdf, do: %Schema{type: :string, format: :binary}
end

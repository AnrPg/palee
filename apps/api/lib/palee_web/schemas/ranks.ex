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
        skills: %Schema{type: :array, maxItems: 20, items: %Schema{type: :string, maxLength: 120}},
        skill_ids: %Schema{
          type: :array,
          maxItems: 20,
          description:
            "Stable id of each skill, in the order of `skills` (ticks keep to it on a rename); null for a new skill",
          items: %Schema{type: :string, nullable: true}
        },
        skill_notes: %Schema{
          type: :array,
          maxItems: 20,
          description:
            "The coach's note on each skill (up to 500 characters), in the order of `skills`",
          items: %Schema{type: :string, nullable: true, maxLength: 500}
        },
        skill_videos: %Schema{
          type: :array,
          maxItems: 20,
          description: "A video link (https) for each skill, in the order of `skills`",
          items: %Schema{type: :string, nullable: true, maxLength: 500}
        }
      }
    }
  end

  @criteria %Schema{
    type: :array,
    minItems: 1,
    maxItems: 3,
    description: "What counts for «Πληροί τις προϋποθέσεις» on this ladder",
    items: %Schema{type: :string, enum: ~w(days classes skills)}
  }

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
        ready_criteria: @criteria,
        ranks: %Schema{type: :array, items: rank()}
      },
      required: [:class_type_ids, :discipline, :id, :name, :ranks, :ready_criteria, :style]
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
        locale: locale(),
        name: %Schema{type: :string, maxLength: 60},
        discipline: %Schema{type: :string},
        style: %Schema{type: :string, enum: ~w(belt level)},
        class_type_ids: %Schema{type: :array, maxItems: 20, items: @uuid},
        position: %Schema{type: :integer, minimum: 0},
        ready_criteria: @criteria,
        ranks: %Schema{type: :array, minItems: 1, maxItems: 30, items: rank_input()}
      }
    }
  end

  @doc "A web language; templates come in it (ADR-400)."
  def locale do
    %Schema{
      type: :string,
      enum: ~w(en el ar ru de es pt-PT he it bg nl fr),
      description: "The language of template names and skills; Greek when left out"
    }
  end

  def template do
    %Schema{
      title: "RankTemplate",
      type: :object,
      description:
        "A ready-made ladder (ADR-400) in the requested language; a starting point the box edits freely",
      properties: %{
        key: %Schema{type: :string},
        name: %Schema{type: :string},
        discipline: %Schema{type: :string},
        family: @maybe_string,
        style: %Schema{type: :string, enum: ~w(belt level)},
        source: %Schema{
          type: :string,
          enum: ~w(federation palee),
          description: "A federation's or school's system, or Palee's own levels"
        },
        system: %Schema{
          type: :string,
          description: "The system it follows, in the requested language"
        },
        ready: %{@criteria | description: "What a ladder copied from it counts by default"},
        ranks: %Schema{
          type: :array,
          items: %Schema{
            type: :object,
            properties: %{
              name: %Schema{type: :string},
              color: @color,
              max_stripes: %Schema{type: :integer},
              requirements: requirements()
            },
            required: [:name, :max_stripes, :requirements]
          }
        }
      },
      required: [:key, :name, :discipline, :style, :source, :system, :ranks, :ready]
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
        templates: %Schema{type: :array, items: template()},
        colors: %Schema{type: :array, items: %Schema{type: :string}},
        box_disciplines: %Schema{
          type: :array,
          description: "The training kinds of the box's profile; the picker shows them first",
          items: %Schema{type: :string}
        }
      },
      required: [:box_disciplines, :colors, :ladders, :templates]
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
            skill_ids: %Schema{type: :array, items: %Schema{type: :string, nullable: true}},
            criteria: @criteria,
            skills_checked: %Schema{
              type: :array,
              description: "ADR-400: the next rank's skills the coach ticked so far",
              items: %Schema{
                type: :object,
                properties: %{
                  skill: %Schema{type: :string, description: "The skill's current text"},
                  skill_id: %Schema{type: :string, nullable: true},
                  checked_on: %Schema{type: :string, format: :date},
                  note: @maybe_string
                },
                required: [:skill, :checked_on]
              }
            },
            all_skills_checked: %Schema{
              type: :boolean,
              description: "Every listed skill is ticked (true when the rank lists none)"
            },
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

  def skill_check_request do
    %Schema{
      title: "RankSkillCheckRequest",
      type: :object,
      description:
        "ADR-400: tick (or untick) one skill of a rank for a client, between promotions",
      properties: %{
        rank_id: @uuid,
        skill_id: %Schema{type: :string, format: :uuid, description: "The skill's stable id"},
        skill: %Schema{
          type: :string,
          minLength: 1,
          maxLength: 120,
          description: "The skill's text, when no `skill_id` is sent"
        },
        checked: %Schema{type: :boolean, description: "false unticks; true when left out"},
        checked_on: %Schema{type: :string, format: :date},
        note: %Schema{type: :string, maxLength: 280, nullable: true}
      },
      required: [:rank_id]
    }
  end

  def batch_check_request do
    %Schema{
      title: "RankSkillBatchRequest",
      type: :object,
      description:
        "One skill for several people at once (a class): only those who work towards its rank change",
      properties: %{
        rank_id: @uuid,
        skill_id: %Schema{type: :string, format: :uuid},
        skill: %Schema{type: :string, minLength: 1, maxLength: 120},
        user_ids: %Schema{type: :array, minItems: 1, maxItems: 100, items: @uuid},
        checked: %Schema{type: :boolean, description: "false unticks; true when left out"},
        checked_on: %Schema{type: :string, format: :date}
      },
      required: [:rank_id, :user_ids]
    }
  end

  def batch_check_response do
    %Schema{
      title: "RankSkillBatchResponse",
      type: :object,
      properties: %{
        updated: %Schema{type: :array, items: @uuid},
        skipped: %Schema{
          type: :array,
          items: %Schema{
            type: :object,
            properties: %{
              user_id: @uuid,
              reason: %Schema{type: :string, enum: ~w(not_your_client other_rank)}
            },
            required: [:user_id, :reason]
          }
        }
      },
      required: [:updated, :skipped]
    }
  end

  def class_skills_response do
    %Schema{
      title: "RankClassSkillsResponse",
      type: :object,
      properties: %{
        ladders: %Schema{type: :array, items: ladder()},
        people: %Schema{
          type: :array,
          items: %Schema{
            type: :object,
            properties: %{
              user_id: @uuid,
              reachable: %Schema{type: :boolean, description: "The coach may tick for them"},
              next_rank_ids: %Schema{type: :array, items: @uuid},
              checked: %Schema{
                type: :array,
                items: %Schema{
                  type: :object,
                  properties: %{rank_id: @uuid, skill_id: @uuid},
                  required: [:rank_id, :skill_id]
                }
              }
            },
            required: [:checked, :next_rank_ids, :reachable, :user_id]
          }
        }
      },
      required: [:ladders, :people]
    }
  end

  def ready_response do
    %Schema{
      title: "RankReadyResponse",
      type: :object,
      description:
        "People who meet what their ladder counts for the next rank; the coach decides",
      properties: %{
        people: %Schema{
          type: :array,
          items: %Schema{
            type: :object,
            properties: %{
              user_id: @uuid,
              nickname: @maybe_string,
              ladder: %Schema{
                type: :object,
                properties: %{
                  id: @uuid,
                  name: %Schema{type: :string},
                  style: %Schema{type: :string}
                },
                required: [:id, :name, :style]
              },
              current: %Schema{
                type: :object,
                properties: %{rank: rank(), stripes: %Schema{type: :integer}},
                required: [:rank, :stripes]
              },
              next: rank(),
              progress: standing().properties.progress
            },
            required: [:current, :ladder, :next, :progress, :user_id]
          }
        }
      },
      required: [:people]
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

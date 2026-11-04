defmodule PaleeWeb.Schemas.Pacer do
  @moduledoc "OpenAPI schemas of «Ο προηγούμενος εαυτός σου»: split marks and the pace line (ADR-374)."

  alias OpenApiSpex.Schema
  alias PaleeWeb.Schemas.Community

  @uuid %Schema{type: :string, format: :uuid}
  @maybe_integer %Schema{type: :integer, nullable: true}
  @maybe_string %Schema{type: :string, nullable: true}

  def body(schema), do: Community.body(schema)
  def error, do: %Schema{type: :object, additionalProperties: true}

  def split_mark do
    %Schema{
      title: "SplitMark",
      type: :object,
      properties: %{
        segment_index: %Schema{type: :integer, minimum: 0},
        round: %Schema{
          type: :integer,
          minimum: 0,
          nullable: true,
          description: "0 or absent: the segment ended; ≥ 1: that round was finished"
        },
        elapsed_ms: %Schema{
          type: :integer,
          minimum: 0,
          description: "Active time since the start, pauses excluded"
        }
      },
      required: [:elapsed_ms, :segment_index]
    }
  end

  def splits_request do
    %Schema{
      title: "SplitMarksRequest",
      type: :object,
      properties: %{
        marks: %Schema{type: :array, minItems: 1, maxItems: 500, items: split_mark()}
      },
      required: [:marks]
    }
  end

  def splits_response do
    %Schema{
      title: "SplitMarksResponse",
      type: :object,
      properties: %{
        stored: %Schema{type: :integer, description: "Marks that were new"},
        total: %Schema{type: :integer, description: "Marks the execution has now"}
      },
      required: [:stored, :total]
    }
  end

  def checkpoint do
    %Schema{
      title: "PaceCheckpoint",
      type: :object,
      properties: %{
        key: %Schema{type: :string, description: "<section ordinal>:<phase>:<round>:<n>"},
        section_ordinal: %Schema{type: :integer},
        section_id: @maybe_string,
        section_name: @maybe_string,
        phase: %Schema{type: :string, enum: ~w(work rest transition)},
        round: %Schema{type: :integer},
        ghost_at_ms: %Schema{type: :integer},
        ghost_lap_ms: %Schema{type: :integer},
        at_ms: @maybe_integer,
        lap_ms: @maybe_integer,
        delta_ms: %Schema{
          type: :integer,
          nullable: true,
          description: "This attempt minus the previous one: negative is ahead"
        }
      },
      required: [:delta_ms, :ghost_at_ms, :ghost_lap_ms, :key, :phase, :round, :section_ordinal]
    }
  end

  def section do
    %Schema{
      title: "PaceSection",
      type: :object,
      properties: %{
        section_ordinal: %Schema{type: :integer},
        section_id: @maybe_string,
        section_name: @maybe_string,
        ghost_ms: %Schema{type: :integer},
        current_ms: @maybe_integer,
        delta_ms: @maybe_integer
      },
      required: [:delta_ms, :ghost_ms, :section_ordinal]
    }
  end

  def pacer do
    %Schema{
      title: "Pacer",
      type: :object,
      properties: %{
        execution_id: @uuid,
        previous: %Schema{
          type: :object,
          nullable: true,
          description: "The attempt raced against; null when there is none",
          properties: %{
            execution_id: @uuid,
            completed_at_utc: %Schema{type: :string, format: :"date-time"},
            completed_at_tz: @maybe_string,
            scale_level_slug: @maybe_string,
            same_workout: %Schema{
              type: :boolean,
              description: "False when it is the same benchmark from another workout"
            }
          },
          required: [:completed_at_utc, :execution_id, :same_workout]
        },
        precision: %Schema{
          type: :string,
          nullable: true,
          enum: ~w(rounds segments sections finish)
        },
        checkpoints: %Schema{type: :array, items: checkpoint()},
        sections: %Schema{type: :array, items: section()},
        ghost_total_ms: @maybe_integer,
        current_total_ms: @maybe_integer,
        total_delta_ms: @maybe_integer
      },
      required: [:checkpoints, :execution_id, :previous, :sections]
    }
  end

  def pacer_response do
    %Schema{
      title: "PacerResponse",
      type: :object,
      properties: %{pacer: pacer()},
      required: [:pacer]
    }
  end
end

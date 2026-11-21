defmodule PaleeWeb.Schemas.WorkoutKinds do
  @moduledoc "OpenAPI schemas and renderers of ADR-690 (box workout types, Palee additions, the queue)."

  alias OpenApiSpex.Schema
  alias Palee.Workouts.Domain.WorkoutType

  @locales ~w(en el de es fr it nl pt_PT ru bg ar he)

  def locales, do: @locales

  def family, do: %Schema{type: :string, enum: WorkoutType.family_keys()}

  def ref,
    do: %Schema{
      type: :string,
      pattern: "^([a-z][a-z0-9_]{1,47}|box:[0-9a-f-]{36})$",
      description: "A workout type reference: a Palee kind key or `box:<id>`"
    }

  def box_kind do
    %Schema{
      title: "BoxWorkoutKind",
      type: :object,
      required: [:id, :ref, :label, :family, :status, :merged_into],
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        ref: ref(),
        label: %Schema{type: :string, description: "As the box typed it, in every language"},
        family: family(),
        status: %Schema{type: :string, enum: ["active", "hidden", "merged"]},
        merged_into: %Schema{type: :string, nullable: true}
      }
    }
  end

  def box_kind_envelope,
    do: %Schema{type: :object, required: [:workout_kind], properties: %{workout_kind: box_kind()}}

  def addition do
    %Schema{
      title: "WorkoutKindAddition",
      type: :object,
      required: [:key, :family, :labels],
      properties: %{
        key: %Schema{type: :string},
        family: family(),
        labels: %Schema{
          type: :object,
          additionalProperties: %Schema{type: :string},
          description: "One label per locale"
        }
      }
    }
  end

  def catalogue do
    %Schema{
      title: "WorkoutKindCatalogue",
      type: :object,
      required: [:additions, :box],
      properties: %{
        additions: %Schema{type: :array, items: addition()},
        box: %Schema{type: :array, items: box_kind()}
      }
    }
  end

  def labels_request do
    %Schema{
      type: :object,
      properties: Map.new(@locales, &{String.to_atom(&1), %Schema{type: :string, maxLength: 80}}),
      additionalProperties: false
    }
  end

  def candidate do
    %Schema{
      title: "WorkoutKindCandidate",
      type: :object,
      required: [
        :id,
        :label,
        :status,
        :boxes,
        :family_votes,
        :profile_suggestions,
        :first_seen_at
      ],
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        label: %Schema{type: :string},
        status: %Schema{type: :string, enum: ["pending", "adopted", "aliased", "kept"]},
        boxes: %Schema{type: :integer, description: "Boxes that made it a type"},
        family_votes: %Schema{
          type: :object,
          additionalProperties: %Schema{type: :integer},
          description: "Family => boxes that chose it"
        },
        profile_suggestions: %Schema{
          type: :integer,
          description: "Public page «Πρότεινέ το» discipline suggestions with this name"
        },
        decision: %Schema{type: :object, nullable: true, additionalProperties: true},
        first_seen_at: %Schema{type: :string, format: :"date-time"},
        decided_at: %Schema{type: :string, format: :"date-time", nullable: true}
      }
    }
  end

  def render_catalogue(%{additions: additions, box: box}) do
    %{additions: Enum.map(additions, &render_addition/1), box: Enum.map(box, &render_box_kind/1)}
  end

  def render_addition(addition),
    do: %{key: addition.key, family: addition.family, labels: addition.labels || %{}}

  def render_box_kind(kind) do
    %{
      id: kind.id,
      ref: kind.ref,
      label: kind.label,
      family: kind.family,
      status: kind.status,
      merged_into: kind.merged_into
    }
  end

  def render_candidate(candidate) do
    %{
      id: candidate.id,
      label: candidate.label,
      status: candidate.status,
      boxes: length(candidate.organization_ids || []),
      family_votes: candidate.family_votes || %{},
      profile_suggestions: length(candidate.profile_suggestion_ids || []),
      decision: candidate.decision,
      first_seen_at: candidate.first_seen_at,
      decided_at: candidate.decided_at
    }
  end
end

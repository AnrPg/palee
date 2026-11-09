defmodule PaleeWeb.Schemas.ExerciseCatalogReview do
  @moduledoc "OpenAPI schemas of the Palee team's exercise catalog review (ADR-461)."

  alias OpenApiSpex.{MediaType, Parameter, RequestBody, Schema}
  alias Palee.Workouts.Domain.ExerciseCatalogReview

  def id,
    do: %Parameter{
      name: :id,
      in: :path,
      required: true,
      schema: %Schema{type: :string, format: :uuid}
    }

  def queue_parameters do
    [
      %Parameter{
        name: :status,
        in: :query,
        required: false,
        schema: %Schema{type: :string, enum: ["pending", "approved", "rejected"]}
      },
      %Parameter{
        name: :min_owners,
        in: :query,
        required: false,
        description: "Only names at least this many people or boxes typed (default 2)",
        schema: %Schema{type: :integer, minimum: 1}
      }
    ]
  end

  def candidate do
    %Schema{
      title: "ExerciseNameCandidate",
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        name: %Schema{type: :string},
        uses_count: %Schema{type: :integer},
        owners_count: %Schema{type: :integer},
        status: %Schema{type: :string, enum: ["pending", "approved", "rejected"]},
        catalog_slug: %Schema{type: :string, nullable: true},
        first_seen_at: %Schema{type: :string, format: :"date-time"},
        last_seen_at: %Schema{type: :string, format: :"date-time"},
        decided_at: %Schema{type: :string, format: :"date-time", nullable: true}
      },
      required: [:id, :name, :uses_count, :owners_count, :status, :catalog_slug]
    }
  end

  def queue do
    %Schema{
      title: "ExerciseNameCandidateQueue",
      type: :object,
      properties: %{
        candidates: %Schema{type: :array, items: candidate()},
        catalog: %Schema{
          type: :array,
          description: "The catalog entries an alias can join",
          items: %Schema{
            type: :object,
            properties: %{
              catalog_slug: %Schema{type: :string},
              name: %Schema{type: :string},
              category: %Schema{type: :string, nullable: true}
            },
            required: [:catalog_slug, :name, :category]
          }
        }
      },
      required: [:candidates, :catalog]
    }
  end

  def decision_body do
    %RequestBody{
      required: true,
      content: %{
        "application/json" => %MediaType{
          schema: %Schema{
            title: "ExerciseNameCandidateDecision",
            type: :object,
            properties: %{
              decision: %Schema{type: :string, enum: ExerciseCatalogReview.decisions()},
              label: %Schema{type: :string, description: "Defaults to the typed name"},
              category: %Schema{type: :string, enum: ExerciseCatalogReview.categories()},
              catalog_slug: %Schema{
                type: :string,
                description: "For an alias: the entry it joins"
              },
              muscles: %Schema{
                type: :array,
                description: "For an entry (ADR-560): the muscles it trains, by role",
                items: muscle_target()
              },
              qualities: %Schema{
                type: :array,
                description: "For an entry (ADR-560): the fitness qualities it develops",
                items: %Schema{type: :string}
              }
            },
            required: [:decision]
          }
        }
      }
    }
  end

  def decided do
    %Schema{
      title: "ExerciseNameCandidateDecided",
      type: :object,
      properties: %{candidate: candidate()},
      required: [:candidate]
    }
  end

  def audit do
    %Schema{
      title: "ExerciseCatalogAudit",
      type: :object,
      properties: %{
        events: %Schema{
          type: :array,
          items: %Schema{
            type: :object,
            properties: %{
              id: %Schema{type: :string, format: :uuid},
              action: %Schema{
                type: :string,
                enum: ["approve_entry", "approve_alias", "reject", "set_targets"]
              },
              actor_user_id: %Schema{type: :string, format: :uuid, nullable: true},
              candidate_id: %Schema{type: :string, format: :uuid, nullable: true},
              catalog_slug: %Schema{type: :string, nullable: true},
              metadata: %Schema{type: :object},
              at: %Schema{type: :string, format: :"date-time"}
            },
            required: [:id, :action, :at]
          }
        }
      },
      required: [:events]
    }
  end

  @role %Schema{type: :string, enum: ["primary", "secondary", "stabilizer"]}

  def muscle_target do
    %Schema{
      title: "ExerciseMuscleTarget",
      type: :object,
      properties: %{
        id: %Schema{type: :string, description: "Taxonomy group or head id"},
        role: @role
      },
      required: [:id, :role]
    }
  end

  def exercise_id,
    do: %Parameter{name: :id, in: :path, required: true, schema: %Schema{type: :string}}

  def exercise do
    %Schema{
      title: "CatalogExercise",
      type: :object,
      properties: %{
        id: %Schema{type: :string},
        label: %Schema{type: :string},
        category: %Schema{type: :string, enum: ExerciseCatalogReview.categories()},
        origin: %Schema{type: :string, enum: ["builtin", "reviewed"]},
        aliases: %Schema{type: :array, items: %Schema{type: :string}},
        search_aliases: %Schema{type: :array, items: %Schema{type: :string}},
        muscles: %Schema{type: :array, items: muscle_target()},
        qualities: %Schema{type: :array, items: %Schema{type: :string}}
      },
      required: [:aliases, :category, :id, :label, :muscles, :origin, :qualities, :search_aliases]
    }
  end

  def exercises do
    %Schema{
      title: "CatalogExercises",
      type: :object,
      properties: %{exercises: %Schema{type: :array, items: exercise()}},
      required: [:exercises]
    }
  end

  def exercise_updated do
    %Schema{
      title: "CatalogExerciseUpdated",
      type: :object,
      properties: %{exercise: exercise()},
      required: [:exercise]
    }
  end

  def targets_body do
    %RequestBody{
      required: true,
      content: %{
        "application/json" => %MediaType{
          schema: %Schema{
            title: "CatalogExerciseTargets",
            type: :object,
            properties: %{
              muscles: %Schema{type: :array, items: muscle_target()},
              qualities: %Schema{type: :array, items: %Schema{type: :string}}
            },
            required: [:muscles, :qualities]
          }
        }
      }
    }
  end
end

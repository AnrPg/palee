defmodule PaleeWeb.Schemas.TrainingFloor do
  @moduledoc """
  OpenAPI schemas of v3.1 «Training and floor» (ADR-356..359): WOD
  leaderboard filters and percentiles, WOD snapshots and day assignment
  tags, the fitness profile, visit badges and calendar invites.
  """

  alias OpenApiSpex.{MediaType, RequestBody, Schema}

  @uuid %Schema{type: :string, format: :uuid}
  @maybe_uuid %Schema{type: :string, format: :uuid, nullable: true}
  @maybe_string %Schema{type: :string, nullable: true}
  @maybe_integer %Schema{type: :integer, nullable: true}
  @maybe_date %Schema{type: :string, format: :date, nullable: true}
  @date %Schema{type: :string, format: :date}
  @datetime %Schema{type: :string, format: :"date-time"}

  def body(schema),
    do: %RequestBody{required: true, content: %{"application/json" => %MediaType{schema: schema}}}

  def error, do: %Schema{type: :object, additionalProperties: true}

  # -- CP-D2: leaderboards ------------------------------------------------------

  def leaderboard_row do
    %Schema{
      title: "WorkoutLeaderboardRow",
      type: :object,
      properties: %{
        rank: @maybe_integer,
        user_id: %Schema{
          type: :string,
          format: :uuid,
          nullable: true,
          description: "Null on the Palee-wide board for everyone but the viewer (ADR-394)"
        },
        nickname: @maybe_string,
        avatar_url: @maybe_string,
        box_name: %Schema{
          type: :string,
          nullable: true,
          description: "The person's box, on the Palee-wide board only (ADR-394)"
        },
        scale_level_slug: @maybe_string,
        value: @maybe_string,
        unit: @maybe_string,
        percentile: %Schema{
          type: :integer,
          nullable: true,
          description: "Share of the other results of the slice this one beat (0-100)"
        },
        top_percent: %Schema{
          type: :integer,
          nullable: true,
          description: "«Top X%»: share of results at this place or better, rounded up"
        },
        me: %Schema{type: :boolean}
      },
      required: [:me, :percentile, :rank, :top_percent, :user_id]
    }
  end

  def leaderboard_profile do
    %Schema{
      title: "LeaderboardProfile",
      type: :object,
      properties: %{
        opted_in: %Schema{type: :boolean},
        division: %Schema{type: :string, enum: ["women", "men", nil], nullable: true},
        birth_year: @maybe_integer
      },
      required: [:birth_year, :division, :opted_in]
    }
  end

  def leaderboard_profile_request do
    %Schema{
      title: "LeaderboardProfileRequest",
      type: :object,
      properties: %{
        division: %Schema{type: :string, enum: ["women", "men", nil], nullable: true},
        birth_year: %Schema{type: :integer, minimum: 1900, maximum: 2100, nullable: true}
      }
    }
  end

  def workout_leaderboard do
    %Schema{
      title: "WorkoutLeaderboard",
      type: :object,
      properties: %{
        workout: %Schema{
          type: :object,
          properties: %{id: @uuid, title: @maybe_string},
          required: [:id]
        },
        section: %Schema{type: :object, nullable: true, additionalProperties: true},
        benchmark: palee_benchmark(),
        palee_consent: %Schema{
          type: :string,
          enum: ["share", "see_only", nil],
          nullable: true,
          description:
            "The viewer's answer about the Palee-wide board; null when not asked yet " <>
              "or when the WOD is not a benchmark (ADR-394)"
        },
        opted_in: %Schema{
          type: :boolean,
          description: "Whether the viewer opted in; without it no comparison is shown"
        },
        profile: %Schema{
          type: :object,
          nullable: true,
          properties: %{division: @maybe_string, birth_year: @maybe_integer}
        },
        filters: %Schema{
          type: :object,
          properties: %{
            division: @maybe_string,
            age_group: @maybe_string,
            scale: @maybe_string,
            scope: %Schema{type: :string, enum: ~w(box branch palee)},
            location_id: @maybe_uuid,
            window: %Schema{type: :string, enum: ~w(day week month year all)},
            date: @date,
            buddies: %Schema{type: :boolean}
          },
          required: [:buddies, :date, :scope, :window]
        },
        options: %Schema{
          type: :object,
          properties: %{
            divisions: %Schema{type: :array, items: %Schema{type: :string}},
            age_groups: %Schema{type: :array, items: %Schema{type: :string}},
            scopes: %Schema{type: :array, items: %Schema{type: :string}},
            windows: %Schema{type: :array, items: %Schema{type: :string}},
            scales: %Schema{
              type: :array,
              items: %Schema{
                type: :object,
                properties: %{slug: %Schema{type: :string}, label: %Schema{type: :string}},
                required: [:label, :slug]
              }
            }
          },
          required: [:age_groups, :divisions, :scales, :scopes, :windows]
        },
        total: %Schema{type: :integer},
        rows: %Schema{type: :array, items: leaderboard_row()},
        me: %Schema{allOf: [leaderboard_row()], nullable: true}
      },
      required: [:filters, :me, :opted_in, :options, :rows, :total, :workout]
    }
  end

  @doc "ADR-394: the benchmark a coach tagged the WOD with, or null."
  def palee_benchmark do
    %Schema{
      title: "PaleeBenchmark",
      type: :object,
      nullable: true,
      properties: %{
        key: %Schema{type: :string},
        group: %Schema{type: :string},
        unit: %Schema{type: :string, enum: ["kg", "reps", "mins_secs"]},
        lower_is_better: %Schema{type: :boolean}
      },
      required: [:group, :key, :lower_is_better, :unit]
    }
  end

  @doc "ADR-394: the person's answer about the Palee-wide board."
  def palee_leaderboard_consent do
    %Schema{
      title: "PaleeLeaderboardConsent",
      type: :object,
      properties: %{
        choice: %Schema{
          type: :string,
          enum: ["share", "see_only", nil],
          nullable: true,
          description:
            "share: others see nickname, box and score; see_only: only you see your place; " <>
              "null: not answered or withdrawn"
        }
      },
      required: [:choice]
    }
  end

  def palee_leaderboard_consent_request do
    %Schema{
      title: "PaleeLeaderboardConsentRequest",
      type: :object,
      properties: %{choice: %Schema{type: :string, enum: ["share", "see_only"]}},
      required: [:choice],
      additionalProperties: false
    }
  end

  # -- CP-D3: WOD snapshots ----------------------------------------------------

  def workout_snapshot do
    %Schema{
      title: "WorkoutSnapshotResponse",
      type: :object,
      properties: %{
        snapshot: %Schema{
          title: "WorkoutSnapshot",
          type: :object,
          properties: %{
            id: @uuid,
            workout_id: @uuid,
            title: @maybe_string,
            content_hash: %Schema{type: :string},
            format_version: %Schema{type: :integer},
            taken_at: @datetime,
            content: %Schema{
              type: :object,
              additionalProperties: true,
              description: "The WOD as it read then (title, type, text, sections, plans, body)"
            }
          },
          required: [:content, :content_hash, :format_version, :id, :taken_at, :workout_id]
        }
      },
      required: [:snapshot]
    }
  end

  @doc "ADR-389: the WOD as one's own run or score performed it, and whether it changed since."
  def workout_as_performed do
    %Schema{
      title: "WorkoutAsPerformed",
      type: :object,
      properties: %{
        snapshot: %Schema{
          allOf: [workout_snapshot().properties.snapshot],
          nullable: true,
          description: "Null for results from before snapshots (ADR-357)"
        },
        changed: %Schema{
          type: :boolean,
          description: "The WOD now reads differently, or no longer exists"
        }
      },
      required: [:changed, :snapshot]
    }
  end

  # -- CP-D6: fitness profile ---------------------------------------------------

  @domains ~w(strength power gymnastics monostructural metcon)

  def fitness_reason do
    %Schema{
      title: "FitnessReason",
      type: :object,
      description: "One benchmark PR and the points it gave",
      properties: %{
        benchmark: %Schema{type: :string},
        domain: %Schema{type: :string, enum: @domains},
        name: %Schema{type: :string, description: "The PR as the person named it"},
        value: %Schema{type: :number, description: "kg (1RM), reps or seconds"},
        unit: %Schema{type: :string, enum: ~w(kg reps mins_secs)},
        estimated: %Schema{type: :boolean, description: "1RM estimated from a multi-rep set"},
        points: %Schema{type: :number},
        anchors: %Schema{
          type: :array,
          items: %Schema{
            type: :object,
            properties: %{value: %Schema{type: :number}, points: %Schema{type: :integer}},
            required: [:points, :value]
          }
        },
        beaten_on: @date,
        age_days: %Schema{type: :integer},
        stale: %Schema{type: :boolean},
        load: %Schema{type: :number, nullable: true, description: "The lift's load in kg"},
        reps: %Schema{type: :integer, nullable: true, description: "The lift's reps"},
        basis: %Schema{
          type: :string,
          enum: ~w(absolute body_weight),
          description: "ADR-395: body_weight reads the lift as a multiple of body weight"
        },
        ratio: %Schema{type: :number, nullable: true, description: "Lift ÷ body weight"},
        body_weight_kg: %Schema{type: :number, nullable: true},
        age_band: @maybe_string,
        age_percent: %Schema{type: :number, nullable: true},
        next: %Schema{
          type: :object,
          nullable: true,
          description: "What the next level takes, in the PR's own unit",
          properties: %{points: %Schema{type: :integer}, value: %Schema{type: :number}},
          required: [:points, :value]
        }
      },
      required: [
        :age_days,
        :basis,
        :anchors,
        :beaten_on,
        :benchmark,
        :domain,
        :estimated,
        :name,
        :points,
        :stale,
        :unit,
        :value
      ]
    }
  end

  def fitness_profile do
    %Schema{
      title: "FitnessProfile",
      type: :object,
      properties: %{
        algorithm: %Schema{
          type: :object,
          properties: %{id: %Schema{type: :string}, version: %Schema{type: :integer}},
          required: [:id, :version]
        },
        division: %Schema{type: :string, enum: ["women", "men", nil], nullable: true},
        neutral_standards: %Schema{type: :boolean},
        overall: %Schema{
          type: :object,
          nullable: true,
          properties: %{
            score: %Schema{type: :integer},
            domains_scored: %Schema{type: :integer},
            reason: %Schema{type: :string},
            change: %Schema{type: :integer, nullable: true}
          },
          required: [:domains_scored, :reason, :score]
        },
        domains: %Schema{
          type: :array,
          items: %Schema{
            title: "FitnessDomain",
            type: :object,
            properties: %{
              domain: %Schema{type: :string, enum: @domains},
              score: @maybe_integer,
              confidence: %Schema{
                type: :string,
                enum: ["low", "medium", "high", nil],
                nullable: true
              },
              stale: %Schema{type: :boolean},
              reasons: %Schema{type: :array, items: fitness_reason()},
              previous_score: @maybe_integer,
              change: @maybe_integer,
              tested: %Schema{type: :boolean, description: "progress_only: has a score"},
              direction: %Schema{
                type: :string,
                enum: ["up", "down", "same", nil],
                nullable: true,
                description: "progress_only: the change without its number"
              }
            },
            description:
              "With display all: score, confidence, stale, reasons (and change with a period). " <>
                "With progress_only: tested and direction only.",
            required: [:domain]
          }
        },
        focus: %Schema{
          type: :array,
          items: %Schema{
            title: "FitnessFocus",
            type: :object,
            additionalProperties: true,
            properties: %{
              domain: %Schema{type: :string, enum: @domains},
              kind: %Schema{
                type: :string,
                enum: ~w(weakest_domain undertrained_quality stale_benchmark untested_domain)
              }
            },
            required: [:domain, :kind]
          }
        },
        injury_caution: %Schema{type: :boolean},
        benchmarks_known: %Schema{type: :integer},
        inputs: %Schema{
          type: :object,
          properties: %{
            body_weight_kg: %Schema{type: :number, nullable: true},
            age_band: @maybe_string,
            age_percent: %Schema{type: :number, nullable: true},
            age_ready: %Schema{type: :boolean, description: "Whether a birth year counts yet"}
          },
          required: [:age_ready, :age_band, :age_percent, :body_weight_kg]
        },
        display: %Schema{
          type: :object,
          properties: %{
            mode: %Schema{type: :string, enum: ~w(all progress_only none)},
            set_by: %Schema{type: :string, enum: ~w(self coach)}
          },
          required: [:mode, :set_by]
        },
        settings: fitness_settings(),
        period_from: @maybe_date
      },
      required: [
        :algorithm,
        :display,
        :inputs,
        :period_from,
        :settings,
        :benchmarks_known,
        :division,
        :domains,
        :focus,
        :injury_caution,
        :neutral_standards,
        :overall
      ]
    }
  end

  # -- ADR-395: fitness card settings -----------------------------------------

  def fitness_settings do
    %Schema{
      title: "FitnessSettings",
      type: :object,
      properties: %{
        body_weight_kg: %Schema{type: :number, nullable: true},
        birth_year: @maybe_integer,
        display: %Schema{type: :string, enum: ~w(all progress_only none)}
      },
      required: [:birth_year, :body_weight_kg, :display]
    }
  end

  def fitness_settings_request do
    %Schema{
      title: "FitnessSettingsRequest",
      type: :object,
      properties: %{
        body_weight_kg: %Schema{type: :number, nullable: true, minimum: 25, maximum: 300},
        birth_year: %Schema{type: :integer, nullable: true, minimum: 1900},
        display: %Schema{type: :string, enum: ~w(all progress_only none)}
      }
    }
  end

  def client_fitness_display do
    %Schema{
      title: "ClientFitnessDisplay",
      type: :object,
      properties: %{
        settings: %Schema{
          type: :object,
          nullable: true,
          description: "The client's own settings (null when they set none)",
          properties: %{
            body_weight_kg: %Schema{type: :number, nullable: true},
            birth_year: @maybe_integer,
            display: %Schema{type: :string, enum: ~w(all progress_only none)}
          },
          required: [:birth_year, :body_weight_kg, :display]
        },
        override: %Schema{type: :string, enum: ["progress_only", "none", nil], nullable: true}
      },
      required: [:override, :settings]
    }
  end

  def client_fitness_display_request do
    %Schema{
      title: "ClientFitnessDisplayRequest",
      type: :object,
      properties: %{
        display: %Schema{
          type: :string,
          enum: ["progress_only", "none", nil],
          nullable: true,
          description: "null gives the choice back to the client"
        }
      },
      required: [:display]
    }
  end

  # -- CP-E1: visit badges ------------------------------------------------------

  @badges ~w(first_visit first_in_class_type guest trial brought_by_member came_via_event came_via_referral)

  def via do
    %Schema{
      title: "VisitVia",
      type: :object,
      nullable: true,
      description: "How a first-time visitor came (referral attribution)",
      properties: %{
        kind: %Schema{type: :string, enum: ~w(event referral)},
        event_id: @maybe_uuid,
        channel: @maybe_string,
        by_user_id: @maybe_uuid,
        by_nickname: @maybe_string
      },
      required: [:kind]
    }
  end

  def visit do
    %Schema{
      title: "VisitBadges",
      type: :object,
      properties: %{
        badges: %Schema{type: :array, items: %Schema{type: :string, enum: @badges}},
        via: via()
      },
      required: [:badges, :via]
    }
  end

  def class_visit_badges do
    %Schema{
      title: "ClassVisitBadges",
      type: :object,
      properties: %{
        slot_id: @uuid,
        people: %Schema{
          type: :array,
          items: %Schema{
            title: "ClassVisitPerson",
            type: :object,
            properties: %{
              booking_id: @uuid,
              user_id: @uuid,
              guest_name: @maybe_string,
              brought_by: %Schema{
                type: :object,
                nullable: true,
                properties: %{user_id: @uuid, nickname: @maybe_string},
                required: [:user_id]
              },
              badges: %Schema{type: :array, items: %Schema{type: :string, enum: @badges}},
              via: via()
            },
            required: [:badges, :booking_id, :brought_by, :guest_name, :user_id, :via]
          }
        }
      },
      required: [:people, :slot_id]
    }
  end

  @doc false
  def shared, do: %{uuid: @uuid, date: @date, maybe_date: @maybe_date, datetime: @datetime}
end

defmodule PaleeWeb.Schemas.Programmes do
  @moduledoc "OpenAPI schemas for the programme marketplace (ADR-370, ADR-371)."

  alias OpenApiSpex.{MediaType, RequestBody, Schema}
  alias Palee.Programmes

  @uuid %Schema{type: :string, format: :uuid}
  @maybe_uuid %Schema{type: :string, format: :uuid, nullable: true}
  @date %Schema{type: :string, format: :date}
  @maybe_datetime %Schema{type: :string, format: :"date-time", nullable: true}
  @maybe_string %Schema{type: :string, nullable: true}
  @int %Schema{type: :integer}
  @maybe_int %Schema{type: :integer, nullable: true}

  def body(schema),
    do: %RequestBody{required: true, content: %{"application/json" => %MediaType{schema: schema}}}

  def error,
    do: %Schema{
      title: "ProgrammeError",
      type: :object,
      properties: %{code: %Schema{type: :string}, error: %Schema{type: :string}},
      required: [:code, :error]
    }

  # ── Programmes ──────────────────────────────────────────────────────────

  defp day_input do
    %Schema{
      title: "ProgrammeDayInput",
      type: :object,
      properties: %{
        day: %Schema{type: :integer, minimum: 0, description: "Day 0 is the start date"},
        workout_id: @uuid
      },
      required: [:day, :workout_id]
    }
  end

  defp version_day do
    %Schema{
      title: "ProgrammeVersionDay",
      type: :object,
      properties: %{
        day: @int,
        workout_id: %Schema{type: :string, format: :uuid, description: "The frozen copy"},
        source_workout_id: @uuid,
        title: @maybe_string,
        summary: @maybe_string
      },
      required: [:day, :workout_id]
    }
  end

  defp equipment_key,
    do: %Schema{
      title: "EquipmentKey",
      type: :string,
      enum: Palee.Workouts.equipment_keys(),
      description: "ADR-542: an equipment key (labels: web messages `Equipment.<key>`)"
    }

  defp equipment_list(description),
    do: %Schema{type: :array, items: equipment_key(), description: description}

  def programme_input(required \\ []) do
    %Schema{
      title: "ProgrammeInput",
      type: :object,
      properties: %{
        title: %Schema{type: :string, minLength: 2, maxLength: 120},
        summary: %Schema{type: :string, maxLength: 600, nullable: true},
        description: %Schema{type: :string, maxLength: 10_000, nullable: true},
        level: %Schema{type: :string, enum: Programmes.levels()},
        goal: %Schema{type: :string, enum: Programmes.goals()},
        equipment: %Schema{
          type: :array,
          items: equipment_key(),
          maxItems: 10,
          description:
            "ADR-542: equipment keys the author adds to the derived «κύριος εξοπλισμός» " <>
              "(shown first)"
        },
        equipment_removed: %Schema{
          type: :array,
          items: equipment_key(),
          maxItems: 30,
          description: "ADR-542: derived equipment keys the author takes away"
        },
        sessions_per_week: %Schema{type: :integer, minimum: 1, maximum: 14, nullable: true},
        price_cents: %Schema{type: :integer, minimum: 0, maximum: 10_000_000},
        currency: %Schema{type: :string, enum: ~w(EUR GBP USD CHF)},
        listing: %Schema{
          type: :string,
          enum: Programmes.listings(),
          description: "box: the box's own page; marketplace: also the cross-business catalogue"
        },
        preview_days: %Schema{type: :integer, minimum: 0, maximum: 14},
        refund_policy: %Schema{type: :string, enum: Programmes.refund_policies()},
        draft_weeks: %Schema{type: :integer, minimum: 1, maximum: 52},
        draft_days: %Schema{type: :array, items: day_input(), maxItems: 1_456}
      },
      required: Enum.sort(required)
    }
  end

  defp counts do
    %Schema{
      type: :object,
      properties: %{
        buyers: @int,
        active: @int,
        currency: @maybe_string,
        gross_cents: @maybe_int,
        refunded_cents: @maybe_int
      },
      required: [:active, :buyers]
    }
  end

  defp rating do
    %Schema{
      title: "ProgrammeRating",
      type: :object,
      properties: %{average: %Schema{type: :number, nullable: true}, count: @int},
      required: [:average, :count]
    }
  end

  def version do
    %Schema{
      title: "ProgrammeVersion",
      type: :object,
      properties: %{
        id: @uuid,
        number: @int,
        weeks: @int,
        days: %Schema{type: :array, items: version_day()},
        changelog: @maybe_string,
        published_at: %Schema{type: :string, format: :"date-time"},
        published_by_id: @maybe_uuid
      },
      required: [:days, :id, :number, :published_at, :weeks]
    }
  end

  @staff_required [
    :currency,
    :draft_days,
    :draft_weeks,
    :goal,
    :id,
    :level,
    :listing,
    :preview_days,
    :price_cents,
    :refund_policy,
    :status,
    :title
  ]

  def staff_programme do
    %Schema{
      title: "StaffProgramme",
      type: :object,
      properties:
        Map.merge(programme_input().properties, %{
          id: @uuid,
          status: %Schema{type: :string, enum: Programmes.statuses()},
          draft_days: %Schema{type: :array, items: day_input()},
          current_version_id: @maybe_uuid,
          published_at: @maybe_datetime,
          archived_at: @maybe_datetime,
          author_id: @maybe_uuid,
          sales: counts(),
          reviews: rating(),
          versions: %Schema{type: :array, items: version()},
          version: version(),
          online_payments: %Schema{type: :boolean},
          readiness: %Schema{type: :array, items: readiness_item()},
          cover_url: %{@maybe_string | description: "ADR-541: the cover; null: the theme strip"},
          cover: %Schema{allOf: [cover()], nullable: true},
          facts: %Schema{
            title: "ProgrammeDerivedFacts",
            type: :object,
            description: "ADR-542: what the draft's WODs give, before the author's choice",
            properties: %{
              equipment: equipment_list("Most used first, at most 5"),
              minutes_per_session: @maybe_int
            },
            required: [:equipment, :minutes_per_session]
          },
          main_equipment: main_equipment(),
          minutes_per_session: minutes_per_session()
        }),
      required: @staff_required ++ [:readiness]
    }
  end

  defp main_equipment,
    do:
      equipment_list(
        "ADR-542: «κύριος εξοπλισμός»: the author's added keys, then the derived ones kept"
      )

  defp minutes_per_session,
    do: %Schema{
      type: :integer,
      nullable: true,
      description:
        "ADR-542: «περίπου ανά προπόνηση», rounded to 5; null unless every WOD has a duration"
    }

  defp readiness_item do
    %Schema{
      title: "ProgrammeReadinessItem",
      type: :object,
      description:
        "ADR-544: what the draft lacks («Λείπουν N πράγματα»); blocking items stop «Δημοσίευση»",
      properties: %{
        key: %Schema{type: :string, enum: ~w(title price days empty_weeks summary)},
        blocking: %Schema{type: :boolean},
        weeks: %Schema{
          type: :array,
          items: @int,
          description: "empty_weeks: the weeks (1-based) without a WOD"
        }
      },
      required: [:blocking, :key, :weeks]
    }
  end

  defp cover_edit do
    %Schema{
      title: "ProgrammeCoverEdit",
      type: :object,
      description:
        "ADR-541: how the cover was made from the original; the crop is in fractions of the " <>
          "original after rotation and has the cover's 16:9 aspect",
      properties: %{
        rotation: %Schema{type: :integer, enum: [0, 90, 180, 270]},
        zoom: %Schema{type: :number, minimum: 1, maximum: 4},
        brightness: %Schema{type: :number, minimum: 0.5, maximum: 1.5},
        crop: %Schema{
          title: "ProgrammeCoverCrop",
          type: :object,
          properties: %{
            x: %Schema{type: :number, minimum: 0, maximum: 1},
            y: %Schema{type: :number, minimum: 0, maximum: 1},
            width: %Schema{type: :number, minimum: 0, maximum: 1},
            height: %Schema{type: :number, minimum: 0, maximum: 1}
          },
          required: [:height, :width, :x, :y]
        }
      }
    }
  end

  def cover do
    %Schema{
      title: "ProgrammeCover",
      type: :object,
      properties: %{
        media_id: @uuid,
        url: @maybe_string,
        original_media_id: @uuid,
        original_url: @maybe_string,
        edit: %Schema{allOf: [cover_edit()], nullable: true},
        aspect: %Schema{type: :string, enum: ["16:9"]}
      },
      required: [:aspect, :edit, :media_id, :original_media_id, :original_url, :url]
    }
  end

  def cover_input do
    %Schema{
      title: "ProgrammeCoverInput",
      type: :object,
      properties: %{
        media_id: %{@uuid | description: "The rendered cover (a ready programme_cover upload)"},
        original_media_id: %{
          @uuid
          | description: "The photo it was made from (default: the same upload)"
        },
        edit: cover_edit()
      },
      required: [:media_id]
    }
  end

  def staff_list,
    do: %Schema{
      title: "StaffProgrammeList",
      type: :object,
      properties: %{programmes: %Schema{type: :array, items: staff_programme()}},
      required: [:programmes]
    }

  def staff_response,
    do: %Schema{
      title: "StaffProgrammeResponse",
      type: :object,
      properties: %{programme: staff_programme()},
      required: [:programme]
    }

  def publish_input,
    do: %Schema{
      title: "ProgrammePublishInput",
      type: :object,
      properties: %{changelog: %Schema{type: :string, maxLength: 600, nullable: true}}
    }

  def purchase do
    %Schema{
      title: "ProgrammePurchase",
      type: :object,
      properties: %{
        id: @uuid,
        programme_id: @uuid,
        version_id: @uuid,
        user_id: @maybe_uuid,
        status: %Schema{type: :string, enum: Programmes.purchase_statuses()},
        price_cents: @int,
        currency: %Schema{type: :string},
        refund_policy: %Schema{type: :string, enum: Programmes.refund_policies()},
        starts_on: @date,
        ends_on: @date,
        payment_intent_id: @maybe_uuid,
        refunded_cents: @int,
        activated_at: @maybe_datetime,
        ended_at: @maybe_datetime,
        end_reason: @maybe_string,
        withdrawal_deadline: @maybe_string,
        inserted_at: %Schema{type: :string, format: :"date-time"},
        title: @maybe_string,
        buyer: %Schema{
          type: :object,
          nullable: true,
          properties: %{id: @uuid, nickname: @maybe_string},
          required: [:id]
        },
        refund: %Schema{
          title: "ProgrammeRefundQuote",
          type: :object,
          nullable: true,
          description: "What giving it up now returns, and under which rule",
          properties: %{
            amount_cents: @int,
            rule: %Schema{type: :string, enum: ~w(withdrawal before_start pro_rata)}
          },
          required: [:amount_cents, :rule]
        },
        version_number: @int,
        weeks: @int,
        days: %Schema{
          type: :array,
          items: %Schema{
            title: "ProgrammePurchaseDay",
            type: :object,
            properties: %{
              day: @int,
              date: @date,
              workout_id: @uuid,
              title: @maybe_string,
              summary: @maybe_string
            },
            required: [:date, :day, :workout_id]
          }
        },
        review: %Schema{allOf: [review()], nullable: true}
      },
      required: [
        :currency,
        :ends_on,
        :id,
        :price_cents,
        :programme_id,
        :refund_policy,
        :refunded_cents,
        :starts_on,
        :status,
        :version_id
      ]
    }
  end

  def purchase_list,
    do: %Schema{
      title: "ProgrammePurchaseList",
      type: :object,
      properties: %{purchases: %Schema{type: :array, items: purchase()}},
      required: [:purchases]
    }

  def purchase_response,
    do: %Schema{
      title: "ProgrammePurchaseResponse",
      type: :object,
      properties: %{purchase: purchase()},
      required: [:purchase]
    }

  # ── The buyer's days (ADR-540) ──────────────────────────────────────────

  defp buyer_day do
    %Schema{
      title: "ProgrammeBuyerDay",
      type: :object,
      properties: %{
        day: %Schema{type: :integer, description: "0-based day of the programme"},
        week: @int,
        weekday: %Schema{type: :integer, description: "0..6 within its week"},
        date: @date,
        status: %Schema{type: :string, enum: Programmes.day_statuses()},
        workouts: %Schema{
          type: :array,
          items: %Schema{
            title: "ProgrammeBuyerDayWorkout",
            type: :object,
            properties: %{
              workout_id: @uuid,
              title: @maybe_string,
              summary: @maybe_string,
              assigned_workout_id: %{
                @maybe_uuid
                | description: "The buyer's assigned workout (open it to start); null if none"
              },
              done: %Schema{type: :boolean}
            },
            required: [:assigned_workout_id, :done, :summary, :title, :workout_id]
          }
        }
      },
      required: [:date, :day, :status, :week, :weekday, :workouts]
    }
  end

  def purchase_days_response do
    %Schema{
      title: "ProgrammePurchaseDays",
      type: :object,
      description:
        "ADR-540: a bought programme as a sequence of days; a training day not done by its " <>
          "date is behind until the buyer does it today or skips it",
      properties: %{
        purchase_id: @uuid,
        today: %{@date | description: "The seller's today"},
        starts_on: @date,
        ends_on: %{@date | description: "Follows the moved days"},
        planned_ends_on: %{@date | description: "The end it was sold with (refunds count on it)"},
        latest_end: %{@date | description: "The cap: moves never end it later"},
        weeks: @int,
        progress: %Schema{
          title: "ProgrammePurchaseProgress",
          type: :object,
          properties: %{
            total: %Schema{type: :integer, description: "Training days"},
            done: @int,
            skipped: @int,
            behind: @int,
            remaining: %Schema{type: :integer, description: "Not done and not skipped"}
          },
          required: [:behind, :done, :remaining, :skipped, :total]
        },
        behind: %Schema{
          title: "ProgrammeBehindDay",
          type: :object,
          nullable: true,
          description: "«Έμεινε πίσω»: the earliest behind day, or null",
          properties: %{
            day: @int,
            week: @int,
            weekday: @int,
            date: @date,
            can_do_today: %Schema{
              type: :boolean,
              description: "False when moving would end the programme after latest_end"
            },
            can_skip: %Schema{type: :boolean}
          },
          required: [:can_do_today, :can_skip, :date, :day, :week, :weekday]
        },
        days: %Schema{type: :array, items: buyer_day()}
      },
      required: [
        :behind,
        :days,
        :ends_on,
        :latest_end,
        :planned_ends_on,
        :progress,
        :purchase_id,
        :starts_on,
        :today,
        :weeks
      ]
    }
  end

  def day_action_input,
    do: %Schema{
      title: "ProgrammeDayActionInput",
      type: :object,
      properties: %{day: %Schema{type: :integer, minimum: 0, maximum: 363}},
      required: [:day]
    }

  def refund_input,
    do: %Schema{
      title: "ProgrammeRefundInput",
      type: :object,
      properties: %{
        amount_cents: %Schema{type: :integer, minimum: 1},
        reason: %Schema{type: :string, maxLength: 300},
        idempotency_key: %Schema{type: :string, minLength: 8, maxLength: 200}
      },
      required: [:amount_cents, :idempotency_key]
    }

  def refund_response,
    do: %Schema{
      title: "ProgrammeRefundResponse",
      type: :object,
      properties: %{
        purchase: purchase(),
        refund: %Schema{type: :object, additionalProperties: true},
        rule: @maybe_string
      },
      required: [:purchase, :refund]
    }

  def review do
    %Schema{
      title: "ProgrammeReview",
      type: :object,
      properties: %{
        id: @uuid,
        rating: %Schema{type: :integer, minimum: 1, maximum: 5},
        body: @maybe_string,
        status: %Schema{type: :string, enum: ~w(published hidden)},
        hidden_reason: @maybe_string,
        version_number: @int,
        inserted_at: %Schema{type: :string, format: :"date-time"},
        updated_at: %Schema{type: :string, format: :"date-time"},
        author: %Schema{
          type: :object,
          nullable: true,
          properties: %{id: @uuid, nickname: @maybe_string}
        }
      },
      required: [:id, :rating, :status, :version_number]
    }
  end

  def review_list,
    do: %Schema{
      title: "ProgrammeReviewList",
      type: :object,
      properties: %{reviews: %Schema{type: :array, items: review()}},
      required: [:reviews]
    }

  def review_response,
    do: %Schema{
      title: "ProgrammeReviewResponse",
      type: :object,
      properties: %{review: review()},
      required: [:review]
    }

  def review_input,
    do: %Schema{
      title: "ProgrammeReviewInput",
      type: :object,
      properties: %{
        rating: %Schema{type: :integer, minimum: 1, maximum: 5},
        body: %Schema{type: :string, maxLength: 1_000, nullable: true}
      },
      required: [:rating]
    }

  def moderation_input,
    do: %Schema{
      title: "ProgrammeReviewModeration",
      type: :object,
      properties: %{
        hidden_reason: %Schema{
          type: :string,
          enum: Programmes.hide_reasons(),
          nullable: true,
          description: "Null shows the review again"
        }
      }
    }

  # ── Buying ──────────────────────────────────────────────────────────────

  def public_programme do
    %Schema{
      title: "PublicProgramme",
      type: :object,
      properties: %{
        id: @uuid,
        title: %Schema{type: :string},
        summary: @maybe_string,
        description: @maybe_string,
        level: %Schema{type: :string},
        goal: %Schema{type: :string},
        equipment: %Schema{type: :array, items: %Schema{type: :string}},
        sessions_per_week: @maybe_int,
        price_cents: @int,
        currency: %Schema{type: :string},
        listing: %Schema{type: :string},
        preview_days: @int,
        refund_policy: %Schema{type: :string},
        published_at: @maybe_datetime,
        weeks: @maybe_int,
        version_number: @maybe_int,
        sessions: @maybe_int,
        reviews: rating(),
        preview: %Schema{
          type: :array,
          items: %Schema{
            title: "ProgrammePreviewDay",
            type: :object,
            properties: %{
              day: @int,
              week: @int,
              weekday: @int,
              title: @maybe_string,
              summary: @maybe_string
            },
            required: [:day, :week, :weekday]
          }
        },
        week_outline: %Schema{
          type: :array,
          items: %Schema{
            type: :object,
            properties: %{week: @int, sessions: @int},
            required: [:sessions, :week]
          }
        },
        latest_reviews: %Schema{type: :array, items: review()},
        cover_url: %{@maybe_string | description: "ADR-541: null shows the theme strip"},
        main_equipment: main_equipment(),
        minutes_per_session: minutes_per_session()
      },
      required: [:currency, :goal, :id, :level, :price_cents, :title]
    }
  end

  def terms_response,
    do: %Schema{
      title: "ProgrammeTerms",
      type: :object,
      properties: %{
        programme: public_programme(),
        available: %Schema{type: :boolean},
        provider: @maybe_string,
        earliest_start: @date,
        latest_start: @date,
        withdrawal_days: @maybe_int,
        start_now_text: @maybe_string,
        refund_rule: %Schema{type: :string},
        refund_text: %Schema{type: :string},
        terms_version: %Schema{type: :string},
        owned: %Schema{
          type: :string,
          format: :uuid,
          nullable: true,
          description: "The buyer's active purchase of it, if any"
        }
      },
      required: [
        :available,
        :earliest_start,
        :latest_start,
        :programme,
        :refund_rule,
        :refund_text,
        :terms_version
      ]
    }

  def buy_input,
    do: %Schema{
      title: "ProgrammeBuyInput",
      type: :object,
      properties: %{
        idempotency_key: %Schema{type: :string, minLength: 8, maxLength: 180},
        starts_on: %Schema{type: :string, format: :date, description: "Today up to 60 days ahead"},
        start_now: %Schema{
          type: :boolean,
          description: "The express request to start, required where withdrawal applies"
        },
        language: %Schema{type: :string, enum: ~w(el en)}
      },
      required: [:idempotency_key]
    }

  def buy_response,
    do: %Schema{
      title: "ProgrammeBuyResponse",
      type: :object,
      properties: %{
        purchase_id: @uuid,
        payment: %Schema{
          type: :object,
          additionalProperties: true,
          description: "The checkout: open its checkout_url on the provider's page"
        }
      },
      required: [:payment, :purchase_id]
    }

  # ── Public ──────────────────────────────────────────────────────────────

  def catalogue_item,
    do: %Schema{
      title: "MarketplaceProgramme",
      type: :object,
      properties: %{
        id: @uuid,
        organization_id: @uuid,
        organization_slug: %Schema{type: :string},
        organization_name: %Schema{type: :string},
        title: %Schema{type: :string},
        summary: @maybe_string,
        level: %Schema{type: :string},
        goal: %Schema{type: :string},
        equipment: %Schema{type: :array, items: %Schema{type: :string}},
        sessions_per_week: @maybe_int,
        price_cents: @int,
        currency: %Schema{type: :string},
        weeks: @int,
        version_number: @int,
        rating_average: %Schema{type: :number, nullable: true},
        rating_count: @int,
        published_at: @maybe_datetime,
        cover_url: @maybe_string,
        main_equipment: main_equipment(),
        minutes_per_session: minutes_per_session()
      },
      required: [
        :currency,
        :id,
        :organization_name,
        :organization_slug,
        :price_cents,
        :title,
        :weeks
      ]
    }

  def catalogue_response,
    do: %Schema{
      title: "MarketplaceProgrammeList",
      type: :object,
      properties: %{
        programmes: %Schema{type: :array, items: catalogue_item()},
        limit: @int,
        offset: @int
      },
      required: [:limit, :offset, :programmes]
    }

  defp box,
    do: %Schema{type: :object, additionalProperties: true, description: "The box's public card"}

  def box_programmes_response,
    do: %Schema{
      title: "BoxProgrammeList",
      type: :object,
      properties: %{box: box(), programmes: %Schema{type: :array, items: public_programme()}},
      required: [:box, :programmes]
    }

  def public_programme_response,
    do: %Schema{
      title: "PublicProgrammeResponse",
      type: :object,
      properties: %{box: box(), programme: public_programme()},
      required: [:box, :programme]
    }
end

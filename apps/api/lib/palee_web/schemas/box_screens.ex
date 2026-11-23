defmodule PaleeWeb.Schemas.BoxScreens do
  @moduledoc "OpenAPI schemas of box screens (ADR-253)."

  alias OpenApiSpex.{MediaType, RequestBody, Schema}
  alias PaleeWeb.Schemas.Workout

  @uuid %Schema{type: :string, format: :uuid}
  @nullable_uuid %Schema{type: :string, format: :uuid, nullable: true}
  @time %Schema{type: :string, format: :"date-time"}
  @nullable_time %Schema{type: :string, format: :"date-time", nullable: true}
  @nullable_text %Schema{type: :string, nullable: true}
  @override_views ["wod", "timer", "leaderboard", "bookings", "class"]

  def uuid, do: @uuid

  def body(schema),
    do: %RequestBody{required: true, content: %{"application/json" => %MediaType{schema: schema}}}

  def error do
    %Schema{
      type: :object,
      properties: %{code: %Schema{type: :string}, error: %Schema{type: :string}},
      required: [:code, :error]
    }
  end

  # ── Staff ───────────────────────────────────────────────────────────────

  def override do
    %Schema{
      title: "BoxScreenOverride",
      type: :object,
      nullable: true,
      description: "What staff pinned on the screen; null when it follows the day automatically",
      properties: %{
        view: %Schema{type: :string, enum: @override_views},
        slot_id: @nullable_uuid,
        until: @nullable_time,
        workout_id: %Schema{
          type: :string,
          format: :uuid,
          nullable: true,
          description: "ADR-746: the class's WOD the pin shows; null follows the class's «Τώρα»"
        },
        split_slot_id: %Schema{
          type: :string,
          format: :uuid,
          nullable: true,
          description: "ADR-746: one more class sharing the screen this once"
        }
      },
      required: [:slot_id, :until, :view]
    }
  end

  @space_and_mode %{
    space_id: %Schema{
      type: :string,
      format: :uuid,
      nullable: true,
      description: "ADR-746: the room the screen follows in automatic; null for the whole branch"
    },
    concurrent_mode: %Schema{
      type: :string,
      enum: ["room", "split"],
      description:
        "ADR-746: classes that run together: `room` shows the screen's room's, `split` side by side"
    }
  }

  def screen do
    %Schema{
      title: "BoxScreen",
      type: :object,
      properties: %{
        id: @uuid,
        name: %Schema{type: :string},
        location_id: %Schema{
          type: :string,
          format: :uuid,
          nullable: true,
          description: "The branch; null for the whole box"
        },
        paired: %Schema{type: :boolean},
        paired_at: @nullable_time,
        last_seen_at: @nullable_time,
        pairing_expires_at: %Schema{
          type: :string,
          format: :"date-time",
          nullable: true,
          description: "When the pending pairing code stops working; null without one"
        },
        space_id: @space_and_mode.space_id,
        concurrent_mode: @space_and_mode.concurrent_mode,
        showing: %Schema{
          type: :object,
          nullable: true,
          description:
            "ADR-746: what the screen shows now (class remote only): its class and whether a timer runs",
          properties: %{
            slot_id: @nullable_uuid,
            view: %Schema{type: :string},
            class_name: @nullable_text,
            coach_name: @nullable_text,
            timer_running: %Schema{type: :boolean}
          },
          required: [:slot_id, :view, :timer_running]
        },
        override: override(),
        focus_changed: %Schema{
          type: :object,
          nullable: true,
          description: "Who last changed what the screen shows, and when",
          properties: %{
            at: @time,
            by: %Schema{
              type: :object,
              nullable: true,
              properties: %{id: @uuid, name: @nullable_text},
              required: [:id, :name]
            }
          },
          required: [:at, :by]
        },
        inserted_at: @time
      },
      required: [
        :focus_changed,
        :id,
        :inserted_at,
        :last_seen_at,
        :location_id,
        :name,
        :override,
        :paired,
        :paired_at,
        :pairing_expires_at
      ]
    }
  end

  def pairing_code do
    %Schema{
      title: "BoxScreenPairingCode",
      type: :object,
      description: "Shown once: typed on the TV within 15 minutes",
      properties: %{
        code: %Schema{type: :string, pattern: "^[A-Z0-9]{4}-[A-Z0-9]{4}$", example: "ACEF-3467"},
        expires_at: @time
      },
      required: [:code, :expires_at]
    }
  end

  def screen_list do
    %Schema{
      type: :object,
      properties: %{
        screens: %Schema{type: :array, items: screen()},
        max_screens: %Schema{type: :integer},
        override_views: %Schema{
          type: :array,
          items: %Schema{type: :string, enum: @override_views}
        }
      },
      required: [:max_screens, :override_views, :screens]
    }
  end

  def screen_response do
    %Schema{type: :object, properties: %{screen: screen()}, required: [:screen]}
  end

  def screen_with_code do
    %Schema{
      type: :object,
      properties: %{screen: screen(), pairing_code: pairing_code()},
      required: [:pairing_code, :screen]
    }
  end

  def create_request do
    %Schema{
      type: :object,
      properties: %{
        name: %Schema{type: :string, minLength: 1, maxLength: 60},
        location_id: @nullable_uuid
      },
      required: [:name]
    }
  end

  def update_request do
    %Schema{
      type: :object,
      properties: %{
        name: %Schema{type: :string, minLength: 1, maxLength: 60},
        location_id: @nullable_uuid,
        space_id: @space_and_mode.space_id,
        concurrent_mode: @space_and_mode.concurrent_mode
      }
    }
  end

  def override_request do
    %Schema{
      type: :object,
      properties: %{
        view: %Schema{type: :string, enum: @override_views},
        slot_id: %Schema{
          type: :string,
          format: :uuid,
          nullable: true,
          description: "One of today's classes on the screen; required for `class`"
        },
        workout_id: %Schema{
          type: :string,
          format: :uuid,
          nullable: true,
          description: "ADR-746: one of the class's WODs; null follows its «Τώρα»"
        },
        split_slot_id: %Schema{
          type: :string,
          format: :uuid,
          nullable: true,
          description: "ADR-746: one more of today's classes sharing the screen"
        },
        until: %Schema{
          type: :string,
          format: :"date-time",
          nullable: true,
          description: "When the screen goes back to automatic (within 24 hours); null to keep it"
        }
      },
      required: [:view]
    }
  end

  # ── One class, from its timer remote ────────────────────────────────────

  def class_screen_list do
    %Schema{
      title: "ClassScreenList",
      type: :object,
      description:
        "The box screens the person may change for this class: its coach (today, screens " <>
          "of the class's branch or the whole box) or staff who manage screens",
      properties: %{
        screens: %Schema{type: :array, items: screen()},
        views: %Schema{
          type: :array,
          description: "What the person may pin: a coach `timer`, `leaderboard` and `wod`",
          items: %Schema{type: :string, enum: @override_views}
        },
        workouts: %Schema{
          type: :array,
          description: "ADR-746: the class's WODs in order, and its «Τώρα»",
          items: %Schema{
            type: :object,
            properties: %{id: @uuid, title: @nullable_text, live: %Schema{type: :boolean}},
            required: [:id, :title, :live]
          }
        },
        together: %Schema{
          type: :array,
          description: "ADR-746: today's other classes that overlap this one (to share a screen)",
          items: %Schema{
            type: :object,
            properties: %{id: @uuid, name: @nullable_text, coach_name: @nullable_text},
            required: [:id, :name, :coach_name]
          }
        }
      },
      required: [:screens, :views]
    }
  end

  def class_override_request do
    %Schema{
      type: :object,
      properties: %{
        view: %Schema{type: :string, enum: @override_views},
        until: %Schema{
          type: :string,
          format: :"date-time",
          nullable: true,
          description: "When the screen goes back to automatic (within 24 hours); null to keep it"
        },
        workout_id: %Schema{
          type: :string,
          format: :uuid,
          nullable: true,
          description: "ADR-746: one of the class's WODs; null follows its «Τώρα»"
        },
        split_slot_id: %Schema{
          type: :string,
          format: :uuid,
          nullable: true,
          description: "ADR-746: share the screen with this class this once"
        }
      },
      required: [:view]
    }
  end

  # ── TV ──────────────────────────────────────────────────────────────────

  def pair_request do
    %Schema{
      type: :object,
      properties: %{code: %Schema{type: :string, minLength: 8, maxLength: 20}},
      required: [:code]
    }
  end

  def token_response do
    %Schema{
      title: "BoxScreenToken",
      type: :object,
      properties: %{token: %Schema{type: :string}, expires_at: @time},
      required: [:expires_at, :token]
    }
  end

  def pair_response do
    %Schema{
      type: :object,
      properties: %{
        token: %Schema{type: :string},
        expires_at: @time,
        screen: %Schema{
          type: :object,
          properties: %{id: @uuid, name: %Schema{type: :string}},
          required: [:id, :name]
        },
        box: %Schema{
          type: :object,
          description: "The box; `id` is the topic of `box_screen:<id>` on `/box_screen_socket`",
          properties: %{id: @uuid, name: %Schema{type: :string}},
          required: [:id, :name]
        }
      },
      required: [:box, :expires_at, :screen, :token]
    }
  end

  defp bookings do
    %Schema{
      type: :object,
      description:
        "First names of booked members who do not hide; hidden people, guests and trials only counted",
      properties: %{
        count: %Schema{type: :integer},
        capacity: %Schema{type: :integer},
        waitlist: %Schema{type: :integer},
        names: %Schema{type: :array, items: %Schema{type: :string}},
        unnamed: %Schema{type: :integer}
      },
      required: [:capacity, :count, :names, :unnamed, :waitlist]
    }
  end

  defp class do
    %Schema{
      title: "BoxScreenClass",
      type: :object,
      properties: %{
        id: @uuid,
        name: @nullable_text,
        class_type: @nullable_text,
        scheduled_at: @time,
        ends_at: @time,
        duration_minutes: %Schema{type: :integer},
        location_id: @nullable_uuid,
        space_id: @nullable_uuid,
        cancelled: %Schema{type: :boolean},
        coach_name: @nullable_text,
        workout_id: @nullable_uuid,
        workout_ids: %Schema{
          type: :array,
          description: "ADR-746: the class's WODs in order",
          items: @uuid
        },
        live_workout_id: %Schema{
          type: :string,
          format: :uuid,
          nullable: true,
          description: "ADR-746: the coach's «Τώρα»"
        },
        bookings: bookings()
      },
      required: [
        :bookings,
        :cancelled,
        :class_type,
        :coach_name,
        :duration_minutes,
        :ends_at,
        :id,
        :location_id,
        :name,
        :scheduled_at,
        :workout_id
      ]
    }
  end

  defp workout do
    %Schema{
      title: "BoxScreenWorkout",
      type: :object,
      properties: %{
        id: @uuid,
        title: @nullable_text,
        type: @nullable_text,
        body: Workout.body_schema()
      },
      required: [:body, :id, :title, :type]
    }
  end

  defp leaderboard do
    %Schema{
      title: "BoxScreenLeaderboard",
      type: :object,
      description: "Only people who opted in to leaderboards; never journal-private results",
      properties: %{
        workout_id: @uuid,
        score: %Schema{
          type: :object,
          nullable: true,
          properties: %{
            name: @nullable_text,
            score_type: @nullable_text,
            unit: @nullable_text
          }
        },
        entries: %Schema{
          type: :array,
          items: %Schema{
            type: :object,
            properties: %{
              rank: %Schema{type: :integer},
              name: %Schema{type: :string, description: "First word of the display name"},
              value: @nullable_text,
              unit: @nullable_text,
              scale_level_slug: @nullable_text
            },
            required: [:name, :rank, :scale_level_slug, :unit, :value]
          }
        }
      },
      required: [:entries, :score, :workout_id]
    }
  end

  def focus do
    %Schema{
      title: "BoxScreenFocus",
      type: :object,
      description:
        "What the screen puts first: automatically (preview, timer, results, idle) or as staff pinned it",
      properties: %{
        source: %Schema{type: :string, enum: ["auto", "staff"]},
        view: %Schema{
          type: :string,
          enum: ["preview", "timer", "results", "idle" | @override_views]
        },
        slot_id: @nullable_uuid,
        until: @nullable_time,
        workout_id: %Schema{
          type: :string,
          format: :uuid,
          nullable: true,
          description: "ADR-746: the WOD shown; null follows the class's «Τώρα»"
        },
        split_slot_id: %Schema{
          type: :string,
          format: :uuid,
          nullable: true,
          description: "ADR-746: a second class shown side by side"
        }
      },
      required: [:slot_id, :source, :until, :view]
    }
  end

  def today do
    %Schema{
      title: "BoxScreenToday",
      type: :object,
      properties: %{
        box: %Schema{
          type: :object,
          description: "The box; `id` is the topic of `box_screen:<id>` on `/box_screen_socket`",
          properties: %{id: @uuid, name: @nullable_text},
          required: [:id, :name]
        },
        screen: %Schema{
          type: :object,
          properties: %{
            id: @uuid,
            name: %Schema{type: :string},
            branch: %Schema{
              type: :object,
              nullable: true,
              properties: %{id: @uuid, name: %Schema{type: :string}},
              required: [:id, :name]
            },
            space_id: @space_and_mode.space_id,
            concurrent_mode: @space_and_mode.concurrent_mode
          },
          required: [:branch, :id, :name]
        },
        date: %Schema{type: :string, format: :date, description: "Today on the box's clock"},
        time_zone: %Schema{type: :string},
        server_now: @time,
        classes: %Schema{type: :array, items: class()},
        workouts: %Schema{type: :array, items: workout()},
        leaderboards: %Schema{type: :array, items: leaderboard()},
        focus: focus()
      },
      required: [
        :box,
        :classes,
        :date,
        :focus,
        :leaderboards,
        :screen,
        :server_now,
        :time_zone,
        :workouts
      ]
    }
  end
end

defmodule PaleeWeb.Schemas.Watch do
  @moduledoc "OpenAPI schemas of the watch companion (ADR-375): pairing, the watch plan, heart rate."

  alias OpenApiSpex.Schema
  alias PaleeWeb.Schemas.Community

  @uuid %Schema{type: :string, format: :uuid}
  @maybe_integer %Schema{type: :integer, nullable: true}
  @maybe_string %Schema{type: :string, nullable: true}
  @maybe_datetime %Schema{type: :string, format: :"date-time", nullable: true}
  @platform %Schema{type: :string, enum: ~w(apple_watch wear_os)}

  def body(schema), do: Community.body(schema)
  def error, do: %Schema{type: :object, additionalProperties: true}
  def platform, do: @platform

  def settings do
    %Schema{
      title: "WatchSettings",
      type: :object,
      properties: %{
        show_heart_rate: %Schema{type: :boolean},
        show_pace: %Schema{type: :boolean, description: "The previous attempt's pace line"},
        haptics: %Schema{type: :boolean},
        max_hr: %Schema{
          type: :integer,
          minimum: 120,
          maximum: 230,
          nullable: true,
          description: "Only with it the results show heart-rate zones"
        }
      }
    }
  end

  def watch do
    %Schema{
      title: "PairedWatch",
      type: :object,
      properties: %{
        platform: @platform,
        device_name: @maybe_string,
        app_version: @maybe_string,
        contract_version: %Schema{type: :integer},
        settings: settings(),
        paired_at: %Schema{type: :string, format: :"date-time"},
        last_seen_at: %Schema{type: :string, format: :"date-time"},
        needs_upgrade: %Schema{type: :boolean}
      },
      required: [
        :contract_version,
        :last_seen_at,
        :needs_upgrade,
        :paired_at,
        :platform,
        :settings
      ]
    }
  end

  def watches_response do
    %Schema{
      title: "PairedWatchesResponse",
      type: :object,
      properties: %{
        contract: %Schema{
          type: :object,
          properties: %{
            version: %Schema{type: :integer},
            platforms: %Schema{type: :array, items: @platform}
          },
          required: [:platforms, :version]
        },
        watches: %Schema{type: :array, items: watch()}
      },
      required: [:contract, :watches]
    }
  end

  def pair_request do
    %Schema{
      title: "PairWatchRequest",
      type: :object,
      properties: %{
        contract_version: %Schema{type: :integer, minimum: 1},
        device_name: %Schema{type: :string, maxLength: 60},
        app_version: %Schema{type: :string, maxLength: 32},
        settings: settings()
      },
      required: [:contract_version]
    }
  end

  def watch_response do
    %Schema{
      title: "PairedWatchResponse",
      type: :object,
      properties: %{watch: watch()},
      required: [:watch]
    }
  end

  def plan_segment do
    %Schema{
      title: "WatchPlanSegment",
      type: :object,
      properties: %{
        index: %Schema{type: :integer},
        kind: %Schema{type: :string},
        phase: %Schema{type: :string},
        duration_seconds: @maybe_integer,
        round: @maybe_integer,
        total_rounds: @maybe_integer,
        section_name: @maybe_string,
        label: @maybe_string,
        label_key: @maybe_string,
        label_params: %Schema{type: :object, additionalProperties: true},
        movements: %Schema{
          type: :array,
          maxItems: 3,
          items: %Schema{
            type: :object,
            properties: %{
              name: %Schema{type: :string},
              amount: %Schema{
                nullable: true,
                oneOf: [%Schema{type: :number}, %Schema{type: :string}]
              },
              unit: @maybe_string
            },
            required: [:name]
          }
        },
        scoreable: %Schema{type: :boolean}
      },
      required: [:index, :kind, :label_params, :movements, :phase, :scoreable]
    }
  end

  def plan do
    %Schema{
      title: "WatchPlan",
      type: :object,
      description: "What the phone hands the watch for one execution (contract version 1)",
      properties: %{
        contract_version: %Schema{type: :integer},
        execution_id: @uuid,
        title: @maybe_string,
        status: %Schema{type: :string, enum: ~w(active paused completed)},
        progress: %Schema{
          type: :object,
          properties: %{
            current_segment_index: %Schema{type: :integer},
            lock_version: %Schema{type: :integer},
            total_elapsed_ms: %Schema{type: :integer},
            paused_elapsed_ms: %Schema{type: :integer},
            segment_started_at_utc: @maybe_datetime
          },
          required: [:current_segment_index, :lock_version, :paused_elapsed_ms, :total_elapsed_ms]
        },
        segments: %Schema{type: :array, items: plan_segment()},
        pace: %Schema{
          type: :array,
          items: %Schema{
            type: :object,
            properties: %{
              key: %Schema{type: :string},
              section_ordinal: %Schema{type: :integer},
              phase: %Schema{type: :string},
              round: %Schema{type: :integer},
              at_ms: %Schema{type: :integer}
            },
            required: [:at_ms, :key, :phase, :round, :section_ordinal]
          }
        },
        commands: %Schema{
          type: :array,
          items: %Schema{type: :string, enum: ~w(next round pause resume finish)}
        },
        heart_rate: %Schema{
          type: :object,
          properties: %{
            enabled: %Schema{type: :boolean},
            interval_ms: %Schema{type: :integer},
            max_hr: @maybe_integer
          },
          required: [:enabled, :interval_ms]
        },
        haptics: %Schema{type: :boolean}
      },
      required: [
        :commands,
        :contract_version,
        :execution_id,
        :haptics,
        :heart_rate,
        :pace,
        :progress,
        :segments,
        :status
      ]
    }
  end

  def plan_response do
    %Schema{
      title: "WatchPlanResponse",
      type: :object,
      properties: %{plan: plan()},
      required: [:plan]
    }
  end

  def heart_rate_request do
    %Schema{
      title: "HeartRateBatchesRequest",
      type: :object,
      properties: %{
        platform: @platform,
        batches: %Schema{
          type: :array,
          minItems: 1,
          maxItems: 30,
          items: %Schema{
            type: :object,
            properties: %{
              sequence: %Schema{type: :integer, minimum: 0},
              started_offset_ms: %Schema{type: :integer, minimum: 0},
              interval_ms: %Schema{type: :integer, minimum: 1000, maximum: 60_000},
              bpm: %Schema{
                type: :array,
                minItems: 1,
                maxItems: 720,
                items: %Schema{type: :integer}
              }
            },
            required: [:bpm, :interval_ms, :sequence, :started_offset_ms]
          }
        }
      },
      required: [:batches, :platform]
    }
  end

  def heart_rate_stored do
    %Schema{
      title: "HeartRateStoredResponse",
      type: :object,
      properties: %{stored: %Schema{type: :integer}, total: %Schema{type: :integer}},
      required: [:stored, :total]
    }
  end

  def heart_rate_summary do
    %Schema{
      title: "HeartRateSummary",
      type: :object,
      properties: %{
        execution_id: @uuid,
        samples: %Schema{type: :integer},
        average_bpm: @maybe_integer,
        max_bpm: @maybe_integer,
        min_bpm: @maybe_integer,
        sections: %Schema{
          type: :array,
          items: %Schema{
            type: :object,
            properties: %{
              section_ordinal: %Schema{type: :integer},
              average_bpm: @maybe_integer,
              max_bpm: @maybe_integer
            },
            required: [:section_ordinal]
          }
        },
        zones: %Schema{
          type: :array,
          items: %Schema{
            type: :object,
            properties: %{zone: %Schema{type: :integer}, ms: %Schema{type: :integer}},
            required: [:ms, :zone]
          }
        }
      },
      required: [:execution_id, :samples, :sections, :zones]
    }
  end

  def heart_rate_summary_response do
    %Schema{
      title: "HeartRateSummaryResponse",
      type: :object,
      properties: %{heart_rate: heart_rate_summary()},
      required: [:heart_rate]
    }
  end

  def offer_request do
    %Schema{
      title: "WatchOfferRequest",
      type: :object,
      description:
        "Sent by the phone when a WOD is opened for execution: which watch it sees and whether it is connected now",
      properties: %{platform: @platform, watch_connected: %Schema{type: :boolean}},
      required: [:platform, :watch_connected]
    }
  end

  def offer_response do
    %Schema{
      title: "WatchOfferResponse",
      type: :object,
      properties: %{
        mode: %Schema{
          type: :string,
          enum: ~w(ask start none),
          description:
            "ask: show «Το χρονόμετρο και στο ρολόι;»; start: put the timer on the watch; none: leave it"
        },
        reason: %Schema{
          type: :string,
          enum:
            ~w(execution_closed watch_not_connected not_checked_in already_started answered_yes answered_no not_answered free_athlete first_wods box_member_after_first_wods)
        },
        answer: %Schema{type: :string, enum: ~w(yes no), nullable: true},
        asked_count: %Schema{type: :integer},
        ask_limit: %Schema{
          type: :integer,
          nullable: true,
          description:
            "Box members are asked this many times; null for free athletes (always asked)"
        }
      },
      required: [:answer, :ask_limit, :asked_count, :mode, :reason]
    }
  end

  def offer_answer_request do
    %Schema{
      title: "WatchOfferAnswerRequest",
      type: :object,
      properties: %{answer: %Schema{type: :string, enum: ~w(yes no)}},
      required: [:answer]
    }
  end

  def offer_answer_response do
    %Schema{
      title: "WatchOfferAnswerResponse",
      type: :object,
      properties: %{
        mode: %Schema{type: :string, enum: ~w(start none)},
        answer: %Schema{type: :string, enum: ~w(yes no)}
      },
      required: [:answer, :mode]
    }
  end
end

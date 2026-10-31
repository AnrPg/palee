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
        user_id: @uuid,
        nickname: @maybe_string,
        avatar_url: @maybe_string,
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
            scope: %Schema{type: :string, enum: ~w(box branch)},
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

  @doc false
  def shared, do: %{uuid: @uuid, date: @date, maybe_date: @maybe_date, datetime: @datetime}
end

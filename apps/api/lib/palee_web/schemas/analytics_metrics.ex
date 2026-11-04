defmodule PaleeWeb.Schemas.AnalyticsMetrics do
  @moduledoc """
  OpenAPI shapes of ADR-462: the staff analytics period and filters, the
  KPI entries by registry key, and the per-metric resets (box and member).
  """

  alias OpenApiSpex.{Parameter, Schema}

  @levels ["beginner", "all_levels", "advanced"]
  @times ["morning", "midday", "afternoon", "evening"]
  @tenure ["lt_3m", "3_12m", "gt_12m"]
  @ages ["under_18", "18_34", "35_44", "45_54", "55_64", "65_plus", "unknown"]
  @genders ["women", "men", "unknown"]

  defp list_parameter(name, description) do
    %Parameter{
      name: name,
      in: :query,
      required: false,
      description: description,
      schema: %Schema{type: :string, maxLength: 7400}
    }
  end

  defp date_parameter(name, description) do
    %Parameter{
      name: name,
      in: :query,
      required: false,
      description: description,
      schema: %Schema{type: :string, format: :date}
    }
  end

  @doc "The period and filter parameters (the branch filter is `LocationScope`)."
  def filter_parameters do
    [
      date_parameter(:from, "First gym-local day of the period (included)"),
      date_parameter(:to, "Last gym-local day of the period (included; default today)"),
      %Parameter{
        name: :days,
        in: :query,
        required: false,
        description: "Without from: the period's length in days, ending at `to` (default 30)",
        schema: %Schema{type: :integer, minimum: 1, maximum: 365}
      },
      list_parameter(:class_type_ids, "Comma-separated class type ids"),
      list_parameter(:levels, "Comma-separated class levels: #{Enum.join(@levels, ", ")}"),
      list_parameter(:coach_ids, "Comma-separated coach user ids"),
      list_parameter(:time_of_day, "Gym-local start: #{Enum.join(@times, ", ")}"),
      list_parameter(:package_families, "Comma-separated package families"),
      list_parameter(:package_ids, "Comma-separated package ids"),
      list_parameter(:tenure_bands, "Time since joining: #{Enum.join(@tenure, ", ")}"),
      list_parameter(
        :age_bands,
        "Opt-in age bands (k-anonymous): #{Enum.join(@ages, ", ")}"
      ),
      list_parameter(:genders, "Opt-in gender (k-anonymous): #{Enum.join(@genders, ", ")}")
    ]
  end

  def metric_key_parameter do
    %Parameter{
      name: :metric_key,
      in: :path,
      required: true,
      description: "A metric key of the registry, e.g. training.class_fill_rate",
      schema: %Schema{type: :string, maxLength: 80}
    }
  end

  def reset_id_parameter do
    %Parameter{
      name: :id,
      in: :path,
      required: true,
      schema: %Schema{type: :string, format: :uuid}
    }
  end

  def history_parameters do
    [
      %Parameter{
        name: :page,
        in: :query,
        required: false,
        schema: %Schema{type: :integer, minimum: 1}
      },
      %Parameter{
        name: :per_page,
        in: :query,
        required: false,
        schema: %Schema{type: :integer, minimum: 1, maximum: 50}
      },
      %Parameter{
        name: :metric_key,
        in: :query,
        required: false,
        schema: %Schema{type: :string, maxLength: 80}
      },
      %Parameter{
        name: :days,
        in: :query,
        required: false,
        description: "Box history: the days before each reset its `before` values cover",
        schema: %Schema{type: :integer, minimum: 1, maximum: 365}
      }
    ]
  end

  @doc "The active reset moment of each metric the member or box reset."
  def baselines_schema do
    %Schema{
      type: :object,
      description: "ADR-462: metric key → the active reset baseline (counted only after it)",
      additionalProperties: %Schema{type: :string, format: :"date-time"}
    }
  end

  @row %Schema{
    type: :object,
    description:
      "A breakdown row by `key`; under an age or gender selection a row of fewer than 5 people is only `{key, suppressed: true}`",
    additionalProperties: true,
    properties: %{
      key: %Schema{oneOf: [%Schema{type: :string}, %Schema{type: :integer}], nullable: true},
      suppressed: %Schema{type: :boolean}
    }
  }

  @kpi %Schema{
    title: "AnalyticsKpi",
    type: :object,
    properties: %{
      key: %Schema{type: :string},
      unit: %Schema{
        type: :string,
        enum: ["count", "percent", "ratio", "cents", "days", "per_1000", "rows"]
      },
      kind: %Schema{type: :string, enum: ["flow", "snapshot", "breakdown"]},
      value: %Schema{
        type: :number,
        nullable: true,
        description: "Nil when not computable or suppressed"
      },
      previous: %Schema{
        type: :number,
        nullable: true,
        description: "The previous equal-length period"
      },
      delta: %Schema{type: :number, nullable: true},
      since: %Schema{
        type: :string,
        format: :"date-time",
        nullable: true,
        description: "The active reset baseline: only data after it counts"
      },
      suppressed: %Schema{
        type: :boolean,
        description: "k-anonymity: fewer than 5 people; no number is returned"
      },
      previous_suppressed: %Schema{type: :boolean},
      rows: %Schema{type: :array, items: @row},
      previous_rows: %Schema{type: :array, items: @row}
    },
    required: [
      :delta,
      :key,
      :kind,
      :previous,
      :previous_rows,
      :previous_suppressed,
      :rows,
      :since,
      :suppressed,
      :unit,
      :value
    ]
  }

  def kpis_schema do
    %Schema{
      type: :object,
      description: "ADR-462: every KPI by its registry key",
      additionalProperties: @kpi
    }
  end

  def period_schema do
    %Schema{
      title: "AnalyticsPeriod",
      type: :object,
      properties: %{
        from: %Schema{type: :string, format: :date},
        to: %Schema{type: :string, format: :date},
        days: %Schema{type: :integer},
        previous_from: %Schema{type: :string, format: :date},
        previous_to: %Schema{type: :string, format: :date},
        time_zone: %Schema{type: :string}
      },
      required: [:days, :from, :previous_from, :previous_to, :time_zone, :to]
    }
  end

  defp strings, do: %Schema{type: :array, items: %Schema{type: :string}}

  def filter_schema do
    %Schema{
      title: "AnalyticsFilter",
      type: :object,
      properties: %{
        v: %Schema{type: :integer},
        from: %Schema{type: :string, format: :date},
        to: %Schema{type: :string, format: :date},
        days: %Schema{type: :integer},
        previous_from: %Schema{type: :string, format: :date},
        previous_to: %Schema{type: :string, format: :date},
        location_ids: strings(),
        class_type_ids: strings(),
        levels: strings(),
        coach_ids: strings(),
        time_of_day: strings(),
        package_families: strings(),
        package_ids: strings(),
        tenure_bands: strings(),
        age_bands: strings(),
        genders: strings()
      },
      required: [
        :age_bands,
        :class_type_ids,
        :coach_ids,
        :days,
        :from,
        :genders,
        :levels,
        :location_ids,
        :package_families,
        :package_ids,
        :previous_from,
        :previous_to,
        :tenure_bands,
        :time_of_day,
        :to,
        :v
      ]
    }
  end

  @doc "A summary response: the KPIs, period and filter, plus the older blocks."
  def summary_response(title) do
    %Schema{
      title: title,
      type: :object,
      additionalProperties: true,
      properties: %{
        kpis: kpis_schema(),
        period: period_schema(),
        filter: filter_schema()
      },
      required: [:filter, :kpis, :period]
    }
  end

  @reset %Schema{
    title: "AnalyticsMetricReset",
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      scope: %Schema{type: :string, enum: ["organization", "member"]},
      metric_key: %Schema{type: :string},
      reset_at: %Schema{type: :string, format: :"date-time"},
      reset_by: %Schema{type: :string, format: :uuid, nullable: true},
      undone_at: %Schema{type: :string, format: :"date-time", nullable: true},
      undone_by: %Schema{type: :string, format: :uuid, nullable: true}
    },
    required: [:id, :metric_key, :reset_at, :reset_by, :scope, :undone_at, :undone_by]
  }

  def reset_response do
    %Schema{
      title: "AnalyticsMetricResetResponse",
      type: :object,
      properties: %{reset: @reset},
      required: [:reset]
    }
  end

  def history_response(title) do
    %Schema{
      title: title,
      type: :object,
      properties: %{
        entries: %Schema{
          type: :array,
          items: %Schema{
            type: :object,
            properties:
              Map.merge(@reset.properties, %{
                active: %Schema{type: :boolean},
                before: %Schema{
                  type: :object,
                  nullable: true,
                  additionalProperties: true,
                  description:
                    "Box history: the metric over the days before the reset (`from`, `to`, `value`, `rows`)"
                }
              }),
            required: [
              :active,
              :id,
              :metric_key,
              :reset_at,
              :reset_by,
              :scope,
              :undone_at,
              :undone_by
            ]
          }
        },
        page: %Schema{type: :integer},
        per_page: %Schema{type: :integer},
        total: %Schema{type: :integer}
      },
      required: [:entries, :page, :per_page, :total]
    }
  end
end

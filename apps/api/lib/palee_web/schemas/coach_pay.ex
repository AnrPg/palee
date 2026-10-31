defmodule PaleeWeb.Schemas.CoachPay do
  @moduledoc "OpenAPI shapes of coach pay and commissions (ADR-341)."

  alias OpenApiSpex.{MediaType, RequestBody, Schema}
  alias Palee.CoachPay

  @uuid %Schema{type: :string, format: :uuid}
  @date %Schema{type: :string, format: :date}
  @time %Schema{type: :string, format: :"date-time", nullable: true}
  @int %Schema{type: :integer}

  def body(schema),
    do: %RequestBody{required: true, content: %{"application/json" => %MediaType{schema: schema}}}

  def rule do
    %Schema{
      type: :object,
      required: [
        :class_type_ids,
        :coach_user_id,
        :count_statuses,
        :currency,
        :id,
        :kind,
        :min_attendees,
        :starts_on
      ],
      properties: %{
        id: @uuid,
        coach_user_id: @uuid,
        coach_name: %Schema{type: :string, nullable: true},
        kind: %Schema{type: :string, enum: CoachPay.rule_kinds()},
        amount_cents: %{@int | nullable: true},
        percent_bps: %{@int | nullable: true},
        currency: %Schema{type: :string},
        class_type_ids: %Schema{type: :array, items: @uuid},
        count_statuses: %Schema{
          type: :array,
          items: %Schema{type: :string, enum: CoachPay.rule_count_statuses()}
        },
        min_attendees: @int,
        max_attendees: %{@int | nullable: true},
        sales_scope: %Schema{type: :string, enum: CoachPay.rule_sales_scopes(), nullable: true},
        starts_on: @date,
        ends_on: %{@date | nullable: true},
        note: %Schema{type: :string, nullable: true},
        archived_at: @time
      }
    }
  end

  def rule_body(required) do
    %Schema{
      type: :object,
      additionalProperties: false,
      required: required,
      properties: %{
        coach_user_id: @uuid,
        kind: %Schema{type: :string, enum: CoachPay.rule_kinds()},
        amount_cents: %Schema{type: :integer, minimum: 1, maximum: 10_000_000, nullable: true},
        percent_bps: %Schema{type: :integer, minimum: 1, maximum: 10_000, nullable: true},
        currency: %Schema{type: :string, minLength: 3, maxLength: 3},
        class_type_ids: %Schema{type: :array, items: @uuid},
        count_statuses: %Schema{
          type: :array,
          minItems: 1,
          items: %Schema{type: :string, enum: CoachPay.rule_count_statuses()}
        },
        min_attendees: %Schema{type: :integer, minimum: 0, maximum: 1_000},
        max_attendees: %Schema{type: :integer, minimum: 1, maximum: 1_000, nullable: true},
        sales_scope: %Schema{type: :string, enum: CoachPay.rule_sales_scopes(), nullable: true},
        starts_on: @date,
        ends_on: %{@date | nullable: true},
        note: %Schema{type: :string, maxLength: 200, nullable: true}
      }
    }
  end

  def rules,
    do: %Schema{
      type: :object,
      required: [:rules],
      properties: %{rules: %Schema{type: :array, items: rule()}}
    }

  def line do
    %Schema{
      type: :object,
      required: [:amount_cents, :description, :id, :kind, :occurred_on, :quantity, :source_type],
      properties: %{
        id: @uuid,
        rule_id: %{@uuid | nullable: true},
        kind: %Schema{
          type: :string,
          enum: CoachPay.rule_kinds() ++ ["clawback", "adjustment"]
        },
        source_type: %Schema{
          type: :string,
          enum: ~w(scheduled_class appointment_slot finance_payment finance_reversal manual)
        },
        source_id: %{@uuid | nullable: true},
        occurred_on: @date,
        description: %Schema{type: :string},
        quantity: @int,
        unit_cents: %{@int | nullable: true},
        base_cents: %{@int | nullable: true},
        percent_bps: %{@int | nullable: true},
        amount_cents: @int
      }
    }
  end

  def statement do
    %Schema{
      type: :object,
      required: [:coach_user_id, :id, :line_count, :lines, :total_cents],
      properties: %{
        id: @uuid,
        coach_user_id: @uuid,
        coach_name: %Schema{type: :string, nullable: true},
        total_cents: @int,
        line_count: @int,
        lines: %Schema{type: :array, items: line()},
        period: %Schema{type: :object, nullable: true}
      }
    }
  end

  def period do
    %Schema{
      type: :object,
      required: [:currency, :ends_on, :id, :starts_on, :status, :total_cents],
      properties: %{
        id: @uuid,
        starts_on: @date,
        ends_on: @date,
        status: %Schema{type: :string, enum: ["draft", "approved", "exported"]},
        currency: %Schema{type: :string},
        total_cents: @int,
        calculated_at: @time,
        approved_at: @time,
        approved_by_id: %{@uuid | nullable: true},
        exported_at: @time,
        reopen_reason: %Schema{type: :string, nullable: true},
        statements: %Schema{type: :array, items: statement()}
      }
    }
  end

  def periods,
    do: %Schema{
      type: :object,
      required: [:periods],
      properties: %{periods: %Schema{type: :array, items: period()}}
    }

  def one(key, schema), do: %Schema{type: :object, required: [key], properties: %{key => schema}}

  def period_body do
    %Schema{
      type: :object,
      additionalProperties: false,
      required: [:ends_on, :starts_on],
      properties: %{starts_on: @date, ends_on: @date}
    }
  end

  def adjustment_body do
    %Schema{
      type: :object,
      additionalProperties: false,
      required: [:amount_cents, :coach_user_id, :description],
      properties: %{
        coach_user_id: @uuid,
        amount_cents: %Schema{type: :integer, minimum: -10_000_000, maximum: 10_000_000},
        description: %Schema{type: :string, minLength: 1, maxLength: 250}
      }
    }
  end

  def reopen_body do
    %Schema{
      type: :object,
      additionalProperties: false,
      required: [:reason],
      properties: %{reason: %Schema{type: :string, minLength: 1, maxLength: 200}}
    }
  end

  def my_statements,
    do: %Schema{
      type: :object,
      required: [:statements],
      properties: %{statements: %Schema{type: :array, items: statement()}}
    }
end

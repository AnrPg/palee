defmodule PaleeWeb.Schemas.CoachPay do
  @moduledoc "OpenAPI shapes of coach pay and commissions (ADR-341, ADR-382)."

  alias OpenApiSpex.{MediaType, RequestBody, Schema}
  alias Palee.CoachPay

  @uuid %Schema{type: :string, format: :uuid}
  @date %Schema{type: :string, format: :date}
  @time %Schema{type: :string, format: :"date-time", nullable: true}
  @int %Schema{type: :integer}
  @basis %Schema{
    type: :string,
    enum: ["gross", "net"],
    description: "Whether the amount is before (gross) or after (net) the person's taxes"
  }

  def body(schema),
    do: %RequestBody{required: true, content: %{"application/json" => %MediaType{schema: schema}}}

  def rule do
    %Schema{
      type: :object,
      required: [
        :amount_basis,
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
        frequency: %Schema{type: :string, enum: CoachPay.rule_frequencies(), nullable: true},
        amount_basis: @basis,
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
        frequency: %Schema{type: :string, enum: CoachPay.rule_frequencies(), nullable: true},
        amount_basis: @basis,
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
      required: [
        :amount_basis,
        :amount_cents,
        :description,
        :deviates_from_default,
        :id,
        :kind,
        :occurred_on,
        :quantity,
        :source_type
      ],
      properties: %{
        id: @uuid,
        rule_id: %{@uuid | nullable: true},
        pay_item_id: %{@uuid | nullable: true},
        kind: %Schema{type: :string, enum: CoachPay.line_kinds()},
        source_type: %Schema{type: :string, enum: CoachPay.line_sources()},
        note: %Schema{type: :string, nullable: true},
        quantity_divisor: %{@int | nullable: true},
        amount_basis: @basis,
        deviates_from_default: %Schema{
          type: :boolean,
          description: "True for a net line (the default is gross): show it marked"
        },
        created_by_id: %{@uuid | nullable: true},
        inserted_at: @time,
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

  def group do
    %Schema{
      type: :object,
      required: [:amount_basis, :amount_cents, :key, :kind, :line_count, :quantity],
      properties: %{
        key: %Schema{type: :string},
        kind: %Schema{type: :string, enum: CoachPay.line_kinds()},
        rule_id: %{@uuid | nullable: true},
        pay_item_id: %{@uuid | nullable: true},
        amount_basis: @basis,
        terms: %Schema{
          type: :object,
          nullable: true,
          description: "The rule's or pay item's terms when the statement was calculated"
        },
        line_count: @int,
        quantity: @int,
        quantity_divisor: %{@int | nullable: true},
        unit_cents: %{@int | nullable: true},
        base_cents: %{@int | nullable: true},
        amount_cents: @int
      }
    }
  end

  def statement do
    %Schema{
      type: :object,
      required: [
        :coach_user_id,
        :gross_cents,
        :groups,
        :id,
        :line_count,
        :lines,
        :net_cents,
        :net_line_count,
        :total_cents
      ],
      properties: %{
        id: @uuid,
        coach_user_id: @uuid,
        coach_name: %Schema{type: :string, nullable: true},
        total_cents: %Schema{
          type: :integer,
          description: "Every line summed whatever its basis; show gross_cents and net_cents"
        },
        gross_cents: @int,
        net_cents: @int,
        line_count: @int,
        net_line_count: @int,
        lines: %Schema{type: :array, items: line()},
        groups: %Schema{type: :array, items: group()},
        period: %Schema{type: :object, nullable: true}
      }
    }
  end

  def period do
    %Schema{
      type: :object,
      required: [
        :currency,
        :ends_on,
        :gross_cents,
        :id,
        :net_cents,
        :starts_on,
        :status,
        :total_cents
      ],
      properties: %{
        id: @uuid,
        starts_on: @date,
        ends_on: @date,
        status: %Schema{type: :string, enum: ["draft", "approved", "exported"]},
        currency: %Schema{type: :string},
        total_cents: @int,
        gross_cents: @int,
        net_cents: @int,
        calculated_at: @time,
        approved_at: @time,
        approved_by_id: %{@uuid | nullable: true},
        exported_at: @time,
        reopen_reason: %Schema{type: :string, nullable: true},
        statements: %Schema{type: :array, items: statement()},
        item_skips: %Schema{
          type: :array,
          description: "ADR-510: recurring allowances taken off a person for this period",
          items: item_skip()
        }
      }
    }
  end

  def item_skip do
    %Schema{
      type: :object,
      required: [:id, :name, :pay_item_id, :user_id],
      properties: %{
        id: @uuid,
        user_id: @uuid,
        pay_item_id: @uuid,
        name: %Schema{type: :string, nullable: true}
      }
    }
  end

  def people do
    %Schema{
      type: :object,
      required: [:people],
      properties: %{
        people: %Schema{
          type: :array,
          items: %Schema{
            type: :object,
            required: [:name, :pay_roles, :user_id],
            properties: %{
              user_id: @uuid,
              name: %Schema{type: :string, nullable: true},
              pay_roles: %Schema{
                type: :array,
                items: %Schema{type: :string, enum: CoachPay.pay_item_roles()}
              }
            }
          }
        }
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
      required: [:amount_cents, :coach_user_id],
      properties: %{
        coach_user_id: @uuid,
        kind: %Schema{
          type: :string,
          enum: ["adjustment", "ad_hoc", "non_taxable_reimbursement"],
          description:
            "adjustment (default): any non-zero amount with a description; ad_hoc and " <>
              "non_taxable_reimbursement: a positive amount with a required note"
        },
        amount_cents: %Schema{type: :integer, minimum: -10_000_000, maximum: 10_000_000},
        description: %Schema{type: :string, minLength: 1, maxLength: 250},
        note: %Schema{type: :string, minLength: 1, maxLength: 500},
        amount_basis: @basis
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
      required: [:statements, :totals],
      properties: %{
        statements: %Schema{type: :array, items: statement()},
        totals: %Schema{
          type: :array,
          items: %Schema{
            type: :object,
            required: [:currency, :gross_cents, :net_cents, :statement_count],
            properties: %{
              currency: %Schema{type: :string},
              statement_count: @int,
              gross_cents: @int,
              net_cents: @int
            }
          }
        }
      }
    }

  def pay_item_line_body do
    %Schema{
      type: :object,
      additionalProperties: false,
      required: [:pay_item_id, :user_id],
      properties: %{
        pay_item_id: @uuid,
        user_id: @uuid,
        quantity: %Schema{type: :integer, minimum: 1, maximum: 1_000},
        minutes: %Schema{
          type: :integer,
          minimum: 1,
          maximum: 10_080,
          description: "One-off overtime only: the minutes worked"
        },
        unit_cents: %Schema{
          type: :integer,
          minimum: 1,
          maximum: 10_000_000,
          description:
            "One-off overtime only: the rate per hour for this line (default: the item's)"
        },
        note: %Schema{type: :string, maxLength: 500, nullable: true},
        amount_basis: @basis
      }
    }
  end

  def line_basis_body do
    %Schema{
      type: :object,
      additionalProperties: false,
      required: [:amount_basis],
      properties: %{amount_basis: @basis}
    }
  end

  def item do
    %Schema{
      type: :object,
      required: [:amount_basis, :amount_cents, :currency, :id, :kind, :name, :roles, :unit],
      properties: %{
        id: @uuid,
        kind: %Schema{type: :string, enum: CoachPay.pay_item_kinds()},
        name: %Schema{type: :string},
        amount_cents: @int,
        unit: %Schema{type: :string, enum: CoachPay.pay_item_units()},
        roles: %Schema{
          type: :array,
          items: %Schema{type: :string, enum: CoachPay.pay_item_roles()}
        },
        weekly_threshold: %{@int | nullable: true},
        frequency: %Schema{
          type: :string,
          enum: CoachPay.pay_item_frequencies(),
          nullable: true,
          description: "Recurring allowance (unit per_period) only"
        },
        currency: %Schema{type: :string},
        amount_basis: @basis,
        archived_at: @time
      }
    }
  end

  def items,
    do: %Schema{
      type: :object,
      required: [:items],
      properties: %{items: %Schema{type: :array, items: item()}}
    }

  def item_body(required) do
    %Schema{
      type: :object,
      additionalProperties: false,
      required: required,
      properties: %{
        kind: %Schema{type: :string, enum: CoachPay.pay_item_kinds()},
        name: %Schema{type: :string, minLength: 1, maxLength: 120},
        amount_cents: %Schema{type: :integer, minimum: 1, maximum: 10_000_000},
        unit: %Schema{
          type: :string,
          enum: CoachPay.pay_item_units(),
          description:
            "overtime: per_hour; allowance: per_period (recurring, added by every " <>
              "calculation) or per_occurrence (a rate added by hand)"
        },
        frequency: %Schema{
          type: :string,
          enum: CoachPay.pay_item_frequencies(),
          nullable: true,
          description:
            "Recurring allowance: once per pay period (`period`, default) or per day, week " <>
              "or month, prorated by the period's days"
        },
        roles: %Schema{
          type: :array,
          minItems: 1,
          items: %Schema{type: :string, enum: CoachPay.pay_item_roles()}
        },
        weekly_threshold: %Schema{
          type: :integer,
          minimum: 0,
          maximum: 168,
          nullable: true,
          description:
            "Overtime: hours a week (Monday to Sunday) before overtime is counted from " <>
              "classes; null keeps it a rate for one-off hours only"
        },
        currency: %Schema{type: :string, minLength: 3, maxLength: 3},
        amount_basis: @basis
      }
    }
  end

  def summary do
    %Schema{
      type: :object,
      required: [:periods],
      properties: %{
        periods: %Schema{
          type: :array,
          items: %Schema{
            type: :object,
            required: [
              :currency,
              :ends_on,
              :gross_cents,
              :id,
              :net_cents,
              :starts_on,
              :statements,
              :status
            ],
            properties: %{
              id: @uuid,
              starts_on: @date,
              ends_on: @date,
              status: %Schema{type: :string, enum: ["draft", "approved", "exported"]},
              currency: %Schema{type: :string},
              total_cents: @int,
              gross_cents: @int,
              net_cents: @int,
              statements: %Schema{
                type: :array,
                items: %Schema{
                  type: :object,
                  required: [:coach_user_id, :gross_cents, :line_count, :net_cents],
                  properties: %{
                    coach_user_id: @uuid,
                    coach_name: %Schema{type: :string, nullable: true},
                    total_cents: @int,
                    gross_cents: @int,
                    net_cents: @int,
                    line_count: @int
                  }
                }
              }
            }
          }
        }
      }
    }
  end
end

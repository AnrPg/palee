defmodule PaleeWeb.Schemas.CardSurcharges do
  @moduledoc "OpenAPI shapes of the box's card surcharge (ADR-340)."

  alias OpenApiSpex.{MediaType, RequestBody, Schema}

  @channels ["online", "terminal", "desk"]
  @rules ["eea_non_consumer", "commercial_only", "credit_only", "any", "none"]

  def body(schema),
    do: %RequestBody{required: true, content: %{"application/json" => %MediaType{schema: schema}}}

  def card do
    %Schema{
      type: :object,
      nullable: true,
      additionalProperties: false,
      description:
        "What the law reads about a card: credit or debit, issuing country, commercial. " <>
          "Unknown values count against a surcharge.",
      properties: %{
        funding: %Schema{type: :string, enum: ["credit", "debit", "prepaid"], nullable: true},
        country: %Schema{type: :string, minLength: 2, maxLength: 2, nullable: true},
        commercial: %Schema{type: :boolean, nullable: true}
      }
    }
  end

  def settings do
    %Schema{
      type: :object,
      required: [
        :at_cost_confirmed,
        :channels,
        :enabled,
        :fixed_cents,
        :percent_bps,
        :region_code
      ],
      properties: %{
        enabled: %Schema{type: :boolean},
        channels: %Schema{type: :array, items: %Schema{type: :string, enum: @channels}},
        percent_bps: %Schema{type: :integer, minimum: 0, maximum: 1_000},
        fixed_cents: %Schema{type: :integer, minimum: 0, maximum: 10_000},
        region_code: %Schema{type: :string, nullable: true},
        at_cost_confirmed: %Schema{type: :boolean}
      }
    }
  end

  def settings_body do
    %Schema{
      type: :object,
      additionalProperties: false,
      description: "Keys left out keep their value.",
      properties: %{
        enabled: %Schema{type: :boolean},
        channels: %Schema{type: :array, items: %Schema{type: :string, enum: @channels}},
        percent_bps: %Schema{type: :integer, minimum: 0, maximum: 1_000},
        fixed_cents: %Schema{type: :integer, minimum: 0, maximum: 10_000},
        region_code: %Schema{type: :string, nullable: true, maxLength: 10},
        at_cost_confirmed: %Schema{type: :boolean}
      }
    }
  end

  def status do
    %Schema{
      type: :object,
      required: [:allowed, :country_code, :law, :saved, :settings],
      properties: %{
        settings: settings(),
        saved: %Schema{type: :boolean},
        allowed: %Schema{type: :boolean, description: "Whether the law allows any surcharge here"},
        country_code: %Schema{type: :string, nullable: true},
        updated_at: %Schema{type: :string, format: :"date-time", nullable: true},
        law: %Schema{
          type: :object,
          required: [:at_cost, :cap_bps, :regime, :region_required, :rule, :sources],
          properties: %{
            regime: %Schema{type: :string},
            rule: %Schema{type: :string, enum: @rules},
            cap_bps: %Schema{type: :integer, nullable: true},
            at_cost: %Schema{type: :boolean},
            region_required: %Schema{type: :boolean},
            sources: %Schema{type: :array, items: %Schema{type: :string}}
          }
        }
      }
    }
  end

  def quote_body do
    %Schema{
      type: :object,
      additionalProperties: false,
      required: [:amount_cents, :channel],
      properties: %{
        channel: %Schema{type: :string, enum: ["online", "desk"]},
        amount_cents: %Schema{type: :integer, minimum: 1, maximum: 10_000_000},
        card: card()
      }
    }
  end

  def quote do
    %Schema{
      type: :object,
      required: [
        :applies,
        :fixed_cents,
        :percent_bps,
        :reason,
        :rule,
        :surcharge_cents,
        :total_cents
      ],
      properties: %{
        applies: %Schema{type: :boolean},
        surcharge_cents: %Schema{type: :integer},
        total_cents: %Schema{type: :integer},
        percent_bps: %Schema{type: :integer},
        fixed_cents: %Schema{type: :integer},
        rule: %Schema{type: :string, enum: @rules},
        reason: %Schema{
          type: :string,
          nullable: true,
          enum: [
            "off",
            "channel_off",
            "not_allowed_here",
            "card_unknown",
            "card_not_surchargeable",
            "zero"
          ]
        }
      }
    }
  end
end

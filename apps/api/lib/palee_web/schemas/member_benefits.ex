defmodule PaleeWeb.Schemas.MemberBenefits do
  @moduledoc "ADR-612: «Δώρο ή χάρη» payloads."

  alias OpenApiSpex.Schema
  alias Palee.Finance.Domain.MemberBenefits

  @states ~w(active upcoming ended revoked given)
  @date %Schema{type: :string, format: :date, nullable: true}
  @at %Schema{type: :string, format: :"date-time"}

  def benefit do
    %Schema{
      title: "MemberBenefit",
      type: :object,
      description:
        "A grant from the insert-only ledger: what was given, by whom (their roles then), when, why and what it touched",
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        action: %Schema{type: :string, enum: ["grant", "revoke"]},
        kind: %Schema{type: :string, enum: MemberBenefits.kinds()},
        state: %Schema{type: :string, enum: @states},
        starts_on: @date,
        ends_on: @date,
        amount_cents: %Schema{type: :integer, nullable: true, minimum: 0},
        details: %Schema{
          type: :object,
          additionalProperties: true,
          description:
            "extra_uses: allowance, quantity, period, usage_entry_id, subscription_id; package: package_id, package_name, pricing, list_price_cents, price_cents, subscription_id; debt_forgiven: invoices"
        },
        reason: %Schema{type: :string, nullable: true},
        given_by_id: %Schema{type: :string, format: :uuid},
        given_by_roles: %Schema{type: :array, items: %Schema{type: :string}},
        given_at: @at,
        request_id: %Schema{type: :string, nullable: true},
        revocation: %Schema{
          type: :object,
          nullable: true,
          properties: %{
            reason: %Schema{type: :string, nullable: true},
            by_id: %Schema{type: :string, format: :uuid},
            by_roles: %Schema{type: :array, items: %Schema{type: :string}},
            at: @at,
            request_id: %Schema{type: :string, nullable: true}
          },
          required: [:at, :by_id, :by_roles, :reason, :request_id]
        }
      },
      required: [
        :action,
        :amount_cents,
        :details,
        :ends_on,
        :given_at,
        :given_by_id,
        :given_by_roles,
        :id,
        :kind,
        :reason,
        :request_id,
        :revocation,
        :starts_on,
        :state
      ]
    }
  end

  def list_response do
    %Schema{
      title: "MemberBenefitsResponse",
      type: :object,
      properties: %{benefits: %Schema{type: :array, items: benefit()}},
      required: [:benefits]
    }
  end

  def one_response do
    %Schema{
      title: "MemberBenefitResponse",
      type: :object,
      properties: %{benefit: benefit(), replayed: %Schema{type: :boolean}},
      required: [:benefit, :replayed]
    }
  end

  def grant_body do
    %Schema{
      title: "MemberBenefitGrant",
      type: :object,
      description:
        "kind grace or free_access: ends_on; extra_uses: allowance, quantity, period; package: package_id, pricing; debt_forgiven: invoice_ids",
      properties: %{
        kind: %Schema{type: :string, enum: MemberBenefits.kinds()},
        reason: %Schema{type: :string, nullable: true, maxLength: 500},
        idempotency_key: %Schema{type: :string, minLength: 8, maxLength: 200},
        ends_on: %Schema{type: :string, format: :date},
        allowance: %Schema{type: :string},
        quantity: %Schema{type: :integer, minimum: 1, maximum: 10_000},
        period: %Schema{type: :string, enum: MemberBenefits.periods()},
        package_id: %Schema{type: :string, format: :uuid},
        pricing: %Schema{
          type: :object,
          properties: %{
            mode: %Schema{type: :string, enum: ["this_period_free", "price"]},
            price_cents: %Schema{type: :integer, minimum: 0}
          },
          required: [:mode]
        },
        invoice_ids: %Schema{type: :array, items: %Schema{type: :string, format: :uuid}}
      },
      required: [:idempotency_key, :kind]
    }
  end

  def revoke_body do
    %Schema{
      title: "MemberBenefitRevoke",
      type: :object,
      properties: %{
        reason: %Schema{type: :string, nullable: true, maxLength: 500},
        idempotency_key: %Schema{type: :string, minLength: 8, maxLength: 200}
      },
      required: [:idempotency_key]
    }
  end
end

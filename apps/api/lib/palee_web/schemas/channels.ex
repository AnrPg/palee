defmodule PaleeWeb.Schemas.Channels do
  @moduledoc "OpenAPI schemas of SMS, Viber and WhatsApp messages from the box (ADR-348..351)."

  alias OpenApiSpex.{MediaType, RequestBody, Schema}

  @text %Schema{type: :string, nullable: true}
  @time %Schema{type: :string, format: :"date-time", nullable: true}
  @channel %Schema{type: :string, enum: ["sms", "viber", "whatsapp"]}
  @purpose %Schema{type: :string, enum: ["service", "marketing"]}
  @uuid %Schema{type: :string, format: :uuid}
  @locales ~w(el en de fr it es nl pt-PT bg ru ar he)

  def body(schema),
    do: %RequestBody{required: true, content: %{"application/json" => %MediaType{schema: schema}}}

  def connection do
    %Schema{
      type: :object,
      nullable: true,
      description: "The box's provider; the secret is never returned (`has_secret`).",
      properties: %{
        provider: %Schema{type: :string},
        account_mode: %Schema{type: :string, enum: ["palee", "own"]},
        account_id: @text,
        base_url: @text,
        sms_sender: @text,
        viber_sender: @text,
        whatsapp_sender: @text,
        channels: %Schema{type: :array, items: @channel},
        channel_order: %Schema{type: :array, items: @channel},
        default_country: %Schema{type: :string},
        monthly_budget_cents: %Schema{
          type: :integer,
          nullable: true,
          description: "The cap the box typed; null until it does, and then nothing is sent (ADR-390)"
        },
        currency: %Schema{type: :string},
        quiet_start: %Schema{type: :string, nullable: true, example: "21:00"},
        quiet_end: %Schema{type: :string, nullable: true, example: "09:00"},
        status: %Schema{type: :string, enum: ["active", "invalid"]},
        error_code: @text,
        last_error: @text,
        checked_at: @time,
        has_secret: %Schema{type: :boolean},
        webhook_url: %Schema{
          type: :string,
          nullable: true,
          description: "The box's own URL for the provider's receipts and replies"
        },
        updated_at: @time
      },
      required: [
        :account_mode,
        :channel_order,
        :channels,
        :default_country,
        :has_secret,
        :monthly_budget_cents,
        :provider,
        :status
      ]
    }
  end

  def usage do
    %Schema{
      type: :object,
      description: "Spend of one month on the box's clock against the cap (cents).",
      properties: %{
        from: %Schema{type: :string, format: :"date-time"},
        to: %Schema{type: :string, format: :"date-time"},
        spent_cents: %Schema{type: :integer},
        messages: %Schema{type: :integer},
        segments: %Schema{
          type: :integer,
          description: "ADR-385: SMS parts of the counted messages"
        },
        by_channel: spend_map(),
        by_source: %Schema{
          spend_map()
          | description: "ADR-385: spend by who sent (`automation`, `staff`, `system`)"
        },
        by_status: %Schema{
          type: :object,
          description: "ADR-385: every message of the month by state, charged or not",
          additionalProperties: %Schema{type: :integer}
        },
        cap_cents: %Schema{type: :integer, nullable: true},
        currency: %Schema{type: :string},
        account_mode: %Schema{type: :string, nullable: true},
        palee_charge_cents: %Schema{
          type: :integer,
          description:
            "ADR-369: what Palee bills the box for the month (messages sent on Palee's account, " <>
              "at the box's price)"
        }
      },
      required: [
        :by_channel,
        :by_source,
        :by_status,
        :currency,
        :from,
        :messages,
        :palee_charge_cents,
        :segments,
        :spent_cents,
        :to
      ]
    }
  end

  defp spend_map do
    %Schema{
      type: :object,
      additionalProperties: %Schema{
        type: :object,
        properties: %{cents: %Schema{type: :integer}, count: %Schema{type: :integer}},
        required: [:cents, :count]
      }
    }
  end

  def settings do
    %Schema{
      type: :object,
      properties: %{
        connection: connection(),
        providers: %Schema{
          type: :array,
          items: %Schema{
            type: :object,
            properties: %{
              provider: %Schema{type: :string},
              channels: %Schema{type: :array, items: @channel},
              account_modes: %Schema{type: :array, items: %Schema{type: :string}}
            },
            required: [:account_modes, :channels, :provider]
          }
        },
        usage: usage()
      },
      required: [:connection, :providers, :usage]
    }
  end

  def settings_body do
    %Schema{
      type: :object,
      additionalProperties: false,
      properties: %{
        provider: %Schema{type: :string, enum: ["sandbox", "brevo"]},
        account_mode: %Schema{type: :string, enum: ["palee", "own"]},
        account_id: %Schema{type: :string, maxLength: 120, nullable: true},
        secret: %Schema{
          type: :string,
          maxLength: 300,
          format: :password,
          description: "The box's own API key (`own`); kept when not sent"
        },
        base_url: %Schema{type: :string, maxLength: 200, nullable: true},
        sms_sender: %Schema{type: :string, maxLength: 20, nullable: true},
        viber_sender: %Schema{type: :string, maxLength: 60, nullable: true},
        whatsapp_sender: %Schema{type: :string, maxLength: 30, nullable: true},
        channels: %Schema{type: :array, items: @channel, maxItems: 3},
        channel_order: %Schema{type: :array, items: @channel, maxItems: 3},
        default_country: %Schema{type: :string, minLength: 2, maxLength: 2},
        monthly_budget_cents: %Schema{
          type: :integer,
          minimum: 0,
          maximum: 1_000_000,
          nullable: true,
          description:
            "The box's own monthly cap in cents; required once a channel is on (no default, ADR-390)"
        },
        quiet_start: %Schema{type: :string, nullable: true, pattern: "^[0-2][0-9]:[0-5][0-9]$"},
        quiet_end: %Schema{type: :string, nullable: true, pattern: "^[0-2][0-9]:[0-5][0-9]$"},
        rotate_webhook: %Schema{type: :boolean}
      },
      required: [:provider]
    }
  end

  def check do
    %Schema{
      type: :object,
      properties: %{
        ok: %Schema{type: :boolean},
        error_code: @text,
        details: %Schema{type: :object, additionalProperties: true}
      },
      required: [:details, :ok]
    }
  end

  def settings_result do
    %Schema{
      type: :object,
      properties: %{connection: connection(), check: check()},
      required: [:check, :connection]
    }
  end

  def template_row do
    %Schema{
      type: :object,
      properties: %{
        locale: %Schema{type: :string},
        channel: %Schema{type: :string, enum: ["any", "whatsapp"]},
        body: %Schema{type: :string},
        provider_template_id: @text,
        variable_names: %Schema{type: :array, items: %Schema{type: :string}},
        approval_status: %Schema{type: :string, enum: ["none", "pending", "approved", "rejected"]},
        updated_at: @time
      },
      required: [:approval_status, :body, :channel, :locale, :variable_names]
    }
  end

  def templates do
    %Schema{
      type: :object,
      properties: %{
        templates: %Schema{
          type: :array,
          items: %Schema{
            type: :object,
            properties: %{
              key: %Schema{type: :string},
              purpose: %Schema{type: :string, nullable: true},
              variables: %Schema{type: :array, items: %Schema{type: :string}},
              defaults: %Schema{type: :object, additionalProperties: %Schema{type: :string}},
              custom: %Schema{type: :array, items: template_row()},
              builtin: %Schema{type: :boolean}
            },
            required: [:builtin, :custom, :defaults, :key, :variables]
          }
        }
      },
      required: [:templates]
    }
  end

  def template_body do
    %Schema{
      type: :object,
      additionalProperties: false,
      properties: %{
        locale: %Schema{type: :string, enum: @locales},
        channel: %Schema{type: :string, enum: ["any", "whatsapp"]},
        body: %Schema{type: :string, maxLength: 1000},
        provider_template_id: %Schema{type: :string, maxLength: 120, nullable: true},
        approval_status: %Schema{type: :string, enum: ["none", "pending", "approved", "rejected"]},
        variable_names: %Schema{type: :array, items: %Schema{type: :string}, maxItems: 20}
      },
      required: [:body, :locale]
    }
  end

  def consent do
    %Schema{
      type: :object,
      properties: %{
        channel: @channel,
        purpose: @purpose,
        granted: %Schema{type: :boolean},
        granted_at: @time,
        withdrawn_at: @time,
        source: @text,
        text_version: @text
      },
      required: [:channel, :granted, :purpose]
    }
  end

  def contact do
    %Schema{
      type: :object,
      nullable: true,
      properties: %{
        id: @uuid,
        user_id: %Schema{type: :string, format: :uuid, nullable: true},
        lead_id: %Schema{type: :string, format: :uuid, nullable: true},
        phone: %Schema{type: :string, description: "Masked for staff; full for the person"},
        country: @text,
        locale: %Schema{type: :string},
        opted_out_at: @time,
        consents: %Schema{type: :array, items: consent()},
        updated_at: @time
      },
      required: [:consents, :id, :locale, :phone]
    }
  end

  def contact_result,
    do: %Schema{type: :object, properties: %{contact: contact()}, required: [:contact]}

  def contacts,
    do: %Schema{
      type: :object,
      properties: %{contacts: %Schema{type: :array, items: contact()}},
      required: [:contacts]
    }

  def contact_body do
    %Schema{
      type: :object,
      additionalProperties: false,
      properties: %{
        user_id: @uuid,
        lead_id: @uuid,
        phone: %Schema{type: :string, maxLength: 32},
        locale: %Schema{type: :string, enum: @locales}
      }
    }
  end

  def consent_body do
    %Schema{
      type: :object,
      additionalProperties: false,
      properties: %{
        channel: @channel,
        purpose: @purpose,
        granted: %Schema{type: :boolean},
        source: %Schema{type: :string, enum: ["staff", "person", "form", "import"]},
        text_version: %Schema{type: :string, maxLength: 40}
      },
      required: [:channel, :granted, :purpose]
    }
  end

  def my_channels do
    %Schema{
      type: :object,
      properties: %{
        contact: contact(),
        channels: %Schema{type: :array, items: @channel, description: "Channels the box uses"}
      },
      required: [:channels, :contact]
    }
  end

  def my_channels_body do
    %Schema{
      type: :object,
      additionalProperties: false,
      properties: %{
        phone: %Schema{type: :string, maxLength: 32},
        locale: %Schema{type: :string, enum: @locales},
        text_version: %Schema{type: :string, maxLength: 40},
        consents: %Schema{
          type: :array,
          maxItems: 6,
          items: %Schema{
            type: :object,
            additionalProperties: false,
            properties: %{channel: @channel, purpose: @purpose, granted: %Schema{type: :boolean}},
            required: [:channel, :granted, :purpose]
          }
        }
      }
    }
  end

  def send_body do
    %Schema{
      type: :object,
      additionalProperties: false,
      properties: %{
        user_id: @uuid,
        lead_id: @uuid,
        template_key: %Schema{type: :string, maxLength: 60, example: "box_message"},
        variables: %Schema{type: :object, additionalProperties: %Schema{type: :string}},
        purpose: @purpose,
        channels: %Schema{type: :array, items: @channel, maxItems: 3},
        urgent: %Schema{type: :boolean},
        idempotency_key: %Schema{type: :string, maxLength: 120},
        source_ref: %Schema{type: :string, maxLength: 120}
      },
      required: [:template_key]
    }
  end

  def preview do
    %Schema{
      type: :object,
      properties: %{
        channel: @channel,
        purpose: @purpose,
        template_key: %Schema{type: :string},
        locale: %Schema{type: :string},
        body: %Schema{type: :string},
        segments: %Schema{type: :integer},
        encoding: %Schema{type: :string, nullable: true, description: "gsm7 or ucs2 (SMS only)"},
        estimated_cost_cents: %Schema{
          type: :integer,
          description:
            "The box's price: the provider's estimate plus Palee's margin on Palee's account (ADR-369)"
        },
        currency: %Schema{type: :string},
        urgent: %Schema{type: :boolean},
        release_at: %Schema{type: :string, format: :"date-time"},
        held_for_quiet_hours: %Schema{type: :boolean},
        replies_possible: %Schema{type: :boolean},
        budget: %Schema{
          type: :object,
          properties: %{
            spent_cents: %Schema{type: :integer},
            cap_cents: %Schema{type: :integer},
            currency: %Schema{type: :string}
          },
          required: [:cap_cents, :currency, :spent_cents]
        },
        contact: contact()
      },
      required: [
        :body,
        :budget,
        :channel,
        :contact,
        :estimated_cost_cents,
        :held_for_quiet_hours,
        :release_at,
        :segments
      ]
    }
  end

  @doc "ADR-385: «Ενημέρωση συμμετεχόντων» of a class."
  def class_notice_body do
    %Schema{
      type: :object,
      additionalProperties: false,
      properties: %{
        slot_id: %Schema{type: :string, format: :uuid},
        kind: %Schema{type: :string, enum: ["cancelled", "changed", "free"]},
        text: %Schema{
          type: :string,
          maxLength: 300,
          description: "The staff's own words; required for `free`"
        },
        urgent: %Schema{
          type: :boolean,
          description: "`free` only: send now, even in quiet hours"
        },
        locale: %Schema{type: :string, maxLength: 10, description: "Language of the app notice"},
        idempotency_key: %Schema{
          type: :string,
          maxLength: 80,
          description: "Sending only: the same key never sends twice"
        }
      },
      required: [:kind, :slot_id]
    }
  end

  def class_notice do
    %Schema{
      type: :object,
      description:
        "Who learns of it: in the app (a push device), by SMS (the rest, with consent) " <>
          "or no way, and what the SMS cost.",
      properties: %{
        slot_id: @uuid,
        kind: %Schema{type: :string, enum: ["cancelled", "changed", "free"]},
        urgent: %Schema{type: :boolean},
        participants: %Schema{type: :integer},
        in_app: %Schema{type: :integer},
        sms: %Schema{type: :integer},
        unreachable: %Schema{type: :integer},
        unreachable_reasons: %Schema{
          type: :object,
          description: "Why, by error code (`channel_consent_missing`…)",
          additionalProperties: %Schema{type: :integer}
        },
        estimated_cost_cents: %Schema{type: :integer},
        currency: %Schema{type: :string},
        budget: %Schema{
          type: :object,
          nullable: true,
          properties: %{
            spent_cents: %Schema{type: :integer},
            cap_cents: %Schema{type: :integer},
            currency: %Schema{type: :string}
          },
          required: [:cap_cents, :currency, :spent_cents]
        },
        sample: %Schema{
          type: :object,
          nullable: true,
          description: "The first SMS: its text, parts and when it leaves",
          properties: %{
            body: %Schema{type: :string},
            segments: %Schema{type: :integer},
            release_at: %Schema{type: :string, format: :"date-time"},
            held_for_quiet_hours: %Schema{type: :boolean}
          },
          required: [:body, :held_for_quiet_hours, :release_at, :segments]
        },
        sms_blocked: %Schema{
          type: :string,
          nullable: true,
          description:
            "The box's own reason no SMS can go (`channels_demo_mode`, " <>
              "`channels_not_connected`, `channel_budget_missing`, `channel_budget_exceeded`…)"
        }
      },
      required: [
        :budget,
        :currency,
        :estimated_cost_cents,
        :in_app,
        :kind,
        :participants,
        :sample,
        :slot_id,
        :sms,
        :sms_blocked,
        :unreachable,
        :unreachable_reasons,
        :urgent
      ]
    }
  end

  def queued do
    %Schema{
      type: :object,
      properties: %{
        id: @uuid,
        channel: @channel,
        purpose: @purpose,
        template_key: %Schema{type: :string},
        status: %Schema{type: :string},
        hold_reason: @text,
        release_at: %Schema{type: :string, format: :"date-time"},
        next_attempt_at: @time,
        segments: %Schema{type: :integer},
        estimated_cost_cents: %Schema{type: :integer},
        currency: %Schema{type: :string},
        source: %Schema{type: :string},
        source_ref: @text
      },
      required: [:channel, :id, :status]
    }
  end

  def message do
    %Schema{
      type: :object,
      properties: %{
        id: @uuid,
        contact_id: @uuid,
        to: %Schema{type: :string, description: "Masked number"},
        channel: @channel,
        purpose: @purpose,
        template_key: %Schema{type: :string},
        locale: %Schema{type: :string},
        body: %Schema{type: :string},
        status: %Schema{
          type: :string,
          enum: ["queued", "sending", "sent", "delivered", "failed", "cancelled"]
        },
        hold_reason: @text,
        urgent: %Schema{type: :boolean},
        attempts: %Schema{type: :integer},
        next_attempt_at: @time,
        provider: %Schema{type: :string},
        account_mode: %Schema{type: :string},
        segments: %Schema{type: :integer},
        estimated_cost_cents: %Schema{type: :integer},
        cost_cents: %Schema{type: :integer, nullable: true},
        currency: %Schema{type: :string},
        error_code: @text,
        source: %Schema{type: :string},
        source_ref: @text,
        created_by_id: %Schema{type: :string, format: :uuid, nullable: true},
        sent_at: @time,
        delivered_at: @time,
        failed_at: @time,
        inserted_at: @time,
        events: %Schema{
          type: :array,
          items: %Schema{
            type: :object,
            properties: %{
              kind: %Schema{type: :string},
              status: %Schema{type: :string},
              provider_status: @text,
              error_code: @text,
              occurred_at: %Schema{type: :string, format: :"date-time"}
            },
            required: [:kind, :occurred_at, :status]
          }
        }
      },
      required: [:body, :channel, :id, :status, :to]
    }
  end

  def messages do
    %Schema{
      type: :object,
      properties: %{
        messages: %Schema{type: :array, items: message()},
        total: %Schema{type: :integer}
      },
      required: [:messages, :total]
    }
  end

  # ── ADR-368: the box's own SMTP email provider ─────────────────────────

  def email_connection do
    %Schema{
      type: :object,
      nullable: true,
      description:
        "The box's own SMTP provider; null when Palee sends the box's email (the default). " <>
          "The password is never returned (`has_secret`).",
      properties: %{
        host: %Schema{type: :string},
        port: %Schema{type: :integer},
        tls_mode: %Schema{type: :string, enum: ["starttls", "tls"]},
        username: %Schema{type: :string},
        from_address: %Schema{type: :string, format: :email},
        from_name: @text,
        reply_to: @text,
        enabled: %Schema{type: :boolean},
        status: %Schema{
          type: :string,
          enum: ["unchecked", "active", "invalid"],
          description: "Mail goes through it only when `enabled` and `active` (`in_use`)"
        },
        in_use: %Schema{type: :boolean},
        error_code: @text,
        checked_at: @time,
        has_secret: %Schema{type: :boolean},
        updated_at: @time
      },
      required: [
        :enabled,
        :from_address,
        :has_secret,
        :host,
        :in_use,
        :port,
        :status,
        :tls_mode,
        :username
      ]
    }
  end

  def email_settings do
    %Schema{
      type: :object,
      properties: %{
        connection: email_connection(),
        ports: %Schema{type: :array, items: %Schema{type: :integer}},
        tls_modes: %Schema{type: :array, items: %Schema{type: :string}},
        dns_guidance: %Schema{
          type: :object,
          description:
            "The DNS records the guide reminds the box of; `key` is a message key " <>
              "(`email_dns.*`) the screen translates",
          properties: %{
            domain: @text,
            steps: %Schema{
              type: :array,
              items: %Schema{
                type: :object,
                properties: %{
                  key: %Schema{type: :string},
                  record: @text,
                  host: @text
                },
                required: [:host, :key, :record]
              }
            }
          },
          required: [:domain, :steps]
        }
      },
      required: [:connection, :dns_guidance, :ports, :tls_modes]
    }
  end

  def email_settings_body do
    %Schema{
      type: :object,
      additionalProperties: false,
      properties: %{
        host: %Schema{type: :string, maxLength: 253},
        port: %Schema{type: :integer, enum: [25, 465, 587, 2525]},
        tls_mode: %Schema{type: :string, enum: ["starttls", "tls"]},
        username: %Schema{type: :string, maxLength: 254},
        secret: %Schema{
          type: :string,
          maxLength: 500,
          format: :password,
          description: "The SMTP password; kept when not sent, never returned"
        },
        from_address: %Schema{type: :string, maxLength: 254},
        from_name: %Schema{type: :string, maxLength: 120, nullable: true},
        reply_to: %Schema{type: :string, maxLength: 254, nullable: true},
        enabled: %Schema{type: :boolean}
      }
    }
  end

  def email_check_result do
    %Schema{
      type: :object,
      properties: %{
        connection: email_connection(),
        check: %Schema{
          type: :object,
          properties: %{ok: %Schema{type: :boolean}, error_code: @text},
          required: [:error_code, :ok]
        }
      },
      required: [:check, :connection]
    }
  end

  # ── ADR-369: Palee's margin (Palee team only) ──────────────────────────

  @margins %Schema{
    type: :object,
    description: "Basis points per channel (2500 = 25 %)",
    properties: %{
      sms: %Schema{type: :integer, minimum: 0, maximum: 100_000},
      viber: %Schema{type: :integer, minimum: 0, maximum: 100_000},
      whatsapp: %Schema{type: :integer, minimum: 0, maximum: 100_000}
    }
  }

  def margins do
    %Schema{
      type: :object,
      properties: %{
        margins_bps: %Schema{@margins | required: [:sms, :viber, :whatsapp]},
        updated_at: @time
      },
      required: [:margins_bps, :updated_at]
    }
  end

  def margins_body do
    %Schema{
      type: :object,
      additionalProperties: false,
      properties: %{margins_bps: %Schema{@margins | additionalProperties: false}},
      required: [:margins_bps]
    }
  end

  def monthly_charge do
    %Schema{
      type: :object,
      description:
        "What Palee charges the box for a month's messages on Palee's account, with the " <>
          "providers' cost (Palee team only)",
      properties: %{
        month: %Schema{type: :string, example: "2026-11"},
        from: %Schema{type: :string, format: :"date-time"},
        to: %Schema{type: :string, format: :"date-time"},
        currency: %Schema{type: :string},
        charge_cents: %Schema{type: :integer},
        provider_cost_cents: %Schema{type: :integer},
        margin_cents: %Schema{type: :integer},
        messages: %Schema{type: :integer},
        by_channel: %Schema{
          type: :object,
          additionalProperties: %Schema{
            type: :object,
            properties: %{
              charge_cents: %Schema{type: :integer},
              provider_cost_cents: %Schema{type: :integer},
              count: %Schema{type: :integer}
            },
            required: [:charge_cents, :count, :provider_cost_cents]
          }
        }
      },
      required: [
        :by_channel,
        :charge_cents,
        :currency,
        :from,
        :margin_cents,
        :messages,
        :month,
        :provider_cost_cents,
        :to
      ]
    }
  end

  # ADR-390: the short link of a marketing SMS (public, no sign-in).
  def unsubscribe do
    %Schema{
      title: "SmsUnsubscribe",
      type: :object,
      description:
        "The box behind a marketing SMS's link and whether offers by SMS are off for the person",
      properties: %{
        box_name: %Schema{type: :string},
        locale: %Schema{type: :string, enum: @locales},
        withdrawn: %Schema{type: :boolean}
      },
      required: [:box_name, :locale, :withdrawn]
    }
  end
end

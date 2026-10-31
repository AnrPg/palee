defmodule PaleeWeb.Schemas.Growth do
  @moduledoc "OpenAPI schemas of leads (ADR-344/345), automations (ADR-346) and members at risk (ADR-347)."

  alias OpenApiSpex.{MediaType, RequestBody, Schema}
  alias Palee.Application.Leads.StaffLeads

  @uuid %Schema{type: :string, format: :uuid}
  @time %Schema{type: :string, format: :"date-time", nullable: true}
  @text %Schema{type: :string, nullable: true}
  @int %Schema{type: :integer}

  def uuid, do: @uuid

  def body(schema),
    do: %RequestBody{required: true, content: %{"application/json" => %MediaType{schema: schema}}}

  def one(key, schema), do: %Schema{type: :object, properties: %{key => schema}, required: [key]}

  defp person do
    %Schema{
      type: :object,
      nullable: true,
      properties: %{user_id: @uuid, display_name: @text, handle: @text, avatar_url: @text},
      required: [:user_id]
    }
  end

  # ── Leads ────────────────────────────────────────────────────────────────

  def consent_input do
    %Schema{
      type: :object,
      description:
        "ADR-345: the consent the person gave on the form. `contact` is required; " <>
          "`marketing` is the separate yes to marketing messages",
      properties: %{
        contact: %Schema{type: :boolean},
        marketing: %Schema{type: :boolean},
        text_version: %Schema{type: :string, maxLength: 40},
        text_hash: %Schema{type: :string, maxLength: 128}
      },
      required: [:contact]
    }
  end

  def public_lead_body do
    %Schema{
      type: :object,
      properties: %{
        name: %Schema{type: :string, maxLength: 200},
        email: %Schema{type: :string, maxLength: 254},
        phone: %Schema{type: :string, maxLength: 40},
        message: %Schema{type: :string, maxLength: 4_000},
        locale: %Schema{type: :string, maxLength: 8},
        interests: %Schema{
          type: :array,
          items: %Schema{type: :string, maxLength: 40},
          maxItems: 10
        },
        campaign: %Schema{type: :string, maxLength: 200},
        kind: %Schema{type: :string, enum: ["trial", "contact"]},
        preferred_time: %Schema{type: :string, maxLength: 120},
        source: %Schema{type: :string, enum: ["form", "join_link"]},
        consent: consent_input(),
        website: %Schema{
          type: :string,
          description: "Spam trap: a hidden field people never fill. Leave empty."
        },
        form_started_at: %Schema{
          type: :string,
          description: "When the form opened (ISO 8601 or unix seconds), for the spam check"
        }
      },
      required: [:consent, :name]
    }
  end

  def public_lead_response do
    %Schema{
      type: :object,
      properties: %{status: %Schema{type: :string, enum: ["received"]}},
      required: [:status]
    }
  end

  def lead_task do
    %Schema{
      type: :object,
      properties: %{
        id: @uuid,
        lead_id: @uuid,
        lead_name: @text,
        title: %Schema{type: :string},
        due_at: %Schema{type: :string, format: :"date-time"},
        done_at: @time,
        assignee: person()
      },
      required: [:assignee, :done_at, :due_at, :id, :lead_id, :title]
    }
  end

  def lead do
    %Schema{
      type: :object,
      properties: %{
        id: @uuid,
        name: %Schema{type: :string},
        email: @text,
        phone: @text,
        message: @text,
        locale: @text,
        stage: %Schema{type: :string, enum: Palee.Leads.stages()},
        source: %Schema{type: :string, enum: Palee.Leads.sources()},
        campaign: @text,
        interests: %Schema{type: :array, items: %Schema{type: :string}},
        owner: person(),
        person: person(),
        lost_reason: %Schema{type: :string, nullable: true, enum: Palee.Leads.lost_reasons()},
        stage_changed_at: %Schema{type: :string, format: :"date-time"},
        converted_at: @time,
        last_contacted_at: @time,
        created_at: %Schema{type: :string, format: :"date-time"},
        consent: %Schema{
          type: :object,
          properties: %{
            contact_at: @time,
            marketing_at: @time,
            marketing_opted_out_at: @time,
            text_version: @text
          },
          required: [:contact_at, :marketing_at, :marketing_opted_out_at, :text_version]
        },
        next_task: %Schema{lead_task() | nullable: true}
      },
      required: [
        :campaign,
        :consent,
        :converted_at,
        :created_at,
        :email,
        :id,
        :interests,
        :last_contacted_at,
        :locale,
        :lost_reason,
        :message,
        :name,
        :next_task,
        :owner,
        :person,
        :phone,
        :source,
        :stage,
        :stage_changed_at
      ]
    }
  end

  def lead_list do
    %Schema{
      type: :object,
      properties: %{
        leads: %Schema{type: :array, items: lead()},
        counts: %Schema{
          type: :object,
          description: "Leads per stage",
          additionalProperties: @int
        }
      },
      required: [:counts, :leads]
    }
  end

  def lead_event do
    %Schema{
      type: :object,
      properties: %{
        id: @uuid,
        kind: %Schema{type: :string, enum: Palee.Leads.event_kinds()},
        data: %Schema{type: :object, additionalProperties: true},
        at: %Schema{type: :string, format: :"date-time"},
        actor: person()
      },
      required: [:actor, :at, :data, :id, :kind]
    }
  end

  def lead_detail do
    %Schema{
      type: :object,
      properties: %{
        lead: lead(),
        tasks: %Schema{type: :array, items: lead_task()},
        events: %Schema{type: :array, items: lead_event()}
      },
      required: [:events, :lead, :tasks]
    }
  end

  def lead_create_body do
    %Schema{
      type: :object,
      properties: %{
        name: %Schema{type: :string, maxLength: 200},
        email: %Schema{type: :string, maxLength: 254},
        phone: %Schema{type: :string, maxLength: 40},
        message: %Schema{type: :string, maxLength: 4_000},
        locale: %Schema{type: :string, maxLength: 8},
        interests: %Schema{type: :array, items: %Schema{type: :string, maxLength: 40}},
        campaign: %Schema{type: :string, maxLength: 200},
        source: %Schema{type: :string, enum: StaffLeads.staff_sources()},
        owner_id: @uuid,
        marketing_consent: %Schema{
          type: :boolean,
          description: "The person said yes to marketing messages (their own words)"
        }
      },
      required: [:name]
    }
  end

  def lead_update_body do
    %Schema{
      type: :object,
      properties: %{
        name: %Schema{type: :string, maxLength: 200},
        email: %Schema{type: :string, maxLength: 254, nullable: true},
        phone: %Schema{type: :string, maxLength: 40, nullable: true},
        message: %Schema{type: :string, maxLength: 4_000, nullable: true},
        interests: %Schema{type: :array, items: %Schema{type: :string, maxLength: 40}},
        owner_id: %Schema{type: :string, format: :uuid, nullable: true}
      }
    }
  end

  def lead_move_body do
    %Schema{
      type: :object,
      properties: %{
        stage: %Schema{type: :string, enum: Palee.Leads.stages() -- ["converted"]},
        lost_reason: %Schema{type: :string, enum: Palee.Leads.lost_reasons()}
      },
      required: [:stage]
    }
  end

  def lead_note_body,
    do: %Schema{
      type: :object,
      properties: %{text: %Schema{type: :string, maxLength: 2_000}},
      required: [:text]
    }

  def lead_contacted_body,
    do: %Schema{
      type: :object,
      properties: %{channel: %Schema{type: :string, enum: StaffLeads.contact_channels()}}
    }

  def lead_task_body do
    %Schema{
      type: :object,
      properties: %{
        title: %Schema{type: :string, maxLength: 160},
        due_at: %Schema{type: :string, format: :"date-time"},
        assignee_id: @uuid
      },
      required: [:due_at, :title]
    }
  end

  def lead_convert_body,
    do: %Schema{type: :object, properties: %{user_id: @uuid}, required: [:user_id]}

  def lead_import_body do
    %Schema{
      type: :object,
      properties: %{
        csv: %Schema{type: :string, maxLength: 2_000_000, description: "The file's text (UTF-8)"},
        dry_run: %Schema{type: :boolean}
      },
      required: [:csv]
    }
  end

  def lead_import_result do
    %Schema{
      type: :object,
      properties: %{
        dry_run: %Schema{type: :boolean},
        created: @int,
        existing: @int,
        invalid: @int,
        rows: %Schema{
          type: :array,
          items: %Schema{
            type: :object,
            properties: %{
              row: @int,
              result: %Schema{type: :string, enum: ~w(created existing invalid valid)},
              errors: %Schema{type: :object, additionalProperties: true}
            },
            required: [:errors, :result, :row]
          }
        }
      },
      required: [:created, :dry_run, :existing, :invalid, :rows]
    }
  end

  # ── Automations ──────────────────────────────────────────────────────────

  def recipe do
    %Schema{
      type: :object,
      properties: %{
        key: %Schema{type: :string, enum: Palee.Automations.recipe_keys()},
        trigger: %Schema{type: :string, description: "A domain event name, or `daily`"},
        audience: %Schema{type: :array, items: %Schema{type: :string, enum: ["member", "lead"]}},
        purpose: %Schema{type: :string, enum: ["service", "marketing"]},
        enabled: %Schema{type: :boolean},
        channels: %Schema{type: :array, items: %Schema{type: :string}},
        default_channels: %Schema{type: :array, items: %Schema{type: :string}},
        delay_minutes: @int,
        default_delay_minutes: @int,
        subject: @text,
        body: @text,
        default_subject: %Schema{type: :string},
        default_body: %Schema{type: :string},
        settings: %Schema{type: :object, additionalProperties: true},
        updated_at: @time,
        stats: %Schema{type: :object, additionalProperties: @int}
      },
      required: [
        :audience,
        :body,
        :channels,
        :default_body,
        :default_channels,
        :default_delay_minutes,
        :default_subject,
        :delay_minutes,
        :enabled,
        :key,
        :purpose,
        :settings,
        :stats,
        :subject,
        :trigger,
        :updated_at
      ]
    }
  end

  def recipe_list do
    %Schema{
      type: :object,
      properties: %{
        recipes: %Schema{type: :array, items: recipe()},
        channels: %Schema{type: :array, items: %Schema{type: :string}},
        placeholders: %Schema{type: :array, items: %Schema{type: :string}},
        stats_days: @int
      },
      required: [:channels, :placeholders, :recipes, :stats_days]
    }
  end

  def recipe_update_body do
    %Schema{
      type: :object,
      properties: %{
        enabled: %Schema{type: :boolean},
        channels: %Schema{type: :array, items: %Schema{type: :string}, minItems: 1},
        delay_minutes: %Schema{type: :integer, nullable: true, minimum: 0, maximum: 43_200},
        subject: %Schema{type: :string, nullable: true, maxLength: 200},
        body: %Schema{type: :string, nullable: true, maxLength: 2_000},
        settings: %Schema{type: :object, additionalProperties: true}
      }
    }
  end

  def recipe_preview_body do
    %Schema{
      type: :object,
      properties: %{
        locale: %Schema{type: :string, maxLength: 8},
        first_name: %Schema{type: :string, maxLength: 60},
        subject: %Schema{type: :string, maxLength: 200},
        body: %Schema{type: :string, maxLength: 2_000}
      }
    }
  end

  def recipe_preview do
    %Schema{
      type: :object,
      properties: %{
        recipe: %Schema{type: :string},
        subject: %Schema{type: :string},
        body: %Schema{type: :string}
      },
      required: [:body, :recipe, :subject]
    }
  end

  def delivery do
    %Schema{
      type: :object,
      properties: %{
        id: @uuid,
        recipe: %Schema{type: :string},
        status: %Schema{type: :string, enum: Palee.Automations.delivery_statuses()},
        channel: @text,
        due_at: %Schema{type: :string, format: :"date-time"},
        sent_at: @time,
        skip_reason: @text,
        attempts: @int,
        recipient: %Schema{
          type: :object,
          properties: %{
            kind: %Schema{type: :string, enum: ["member", "lead"]},
            user_id: %Schema{type: :string, format: :uuid, nullable: true},
            lead_id: %Schema{type: :string, format: :uuid, nullable: true},
            name: @text
          },
          required: [:kind, :lead_id, :name, :user_id]
        }
      },
      required: [
        :attempts,
        :channel,
        :due_at,
        :id,
        :recipe,
        :recipient,
        :sent_at,
        :skip_reason,
        :status
      ]
    }
  end

  def my_preferences do
    %Schema{
      type: :object,
      properties: %{
        opted_out: %Schema{type: :boolean},
        opted_out_recipes: %Schema{type: :array, items: %Schema{type: :string}},
        birthday: %Schema{
          type: :object,
          nullable: true,
          properties: %{month: @int, day: @int},
          required: [:day, :month]
        },
        recipes: %Schema{
          type: :array,
          items: %Schema{
            type: :object,
            properties: %{key: %Schema{type: :string}, purpose: %Schema{type: :string}},
            required: [:key, :purpose]
          }
        }
      },
      required: [:birthday, :opted_out, :opted_out_recipes, :recipes]
    }
  end

  def my_preferences_body do
    %Schema{
      type: :object,
      properties: %{
        opted_out: %Schema{type: :boolean},
        opted_out_recipes: %Schema{
          type: :array,
          items: %Schema{type: :string, enum: Palee.Automations.recipe_keys()}
        },
        birthday: %Schema{
          type: :object,
          nullable: true,
          description: "Day and month only, never the year; null stops sharing it",
          properties: %{
            month: %Schema{type: :integer, minimum: 1, maximum: 12},
            day: %Schema{type: :integer, minimum: 1, maximum: 31}
          },
          required: [:day, :month]
        }
      }
    }
  end

  # ── Members at risk ──────────────────────────────────────────────────────

  def risk do
    %Schema{
      type: :object,
      properties: %{
        user_id: @uuid,
        person: person(),
        score: %Schema{type: :integer, minimum: 0, maximum: 100},
        level: %Schema{type: :string, enum: Palee.Retention.levels()},
        reasons: %Schema{
          type: :array,
          items: %Schema{
            type: :object,
            properties: %{
              code: %Schema{type: :string, enum: Palee.Retention.reason_codes()},
              points: @int,
              facts: %Schema{type: :object, additionalProperties: true}
            },
            required: [:code, :facts, :points]
          }
        },
        suggested_action: %Schema{type: :string, enum: Palee.Retention.actions()},
        computed_at: %Schema{type: :string, format: :"date-time"},
        level_since: %Schema{type: :string, format: :"date-time"},
        snoozed_until: %Schema{type: :string, format: :date, nullable: true},
        contacted_at: @time,
        contacted_by: person(),
        win_back_queued_at: @time
      },
      required: [
        :computed_at,
        :contacted_at,
        :contacted_by,
        :level,
        :level_since,
        :person,
        :reasons,
        :score,
        :snoozed_until,
        :suggested_action,
        :user_id,
        :win_back_queued_at
      ]
    }
  end

  def risk_list do
    %Schema{
      type: :object,
      properties: %{
        members: %Schema{type: :array, items: risk()},
        counts: %Schema{type: :object, additionalProperties: @int},
        computed_at: @time
      },
      required: [:computed_at, :counts, :members]
    }
  end

  def risk_contacted_body,
    do: %Schema{
      type: :object,
      properties: %{channel: %Schema{type: :string, enum: ~w(phone email message in_person)}}
    }

  def risk_snooze_body,
    do: %Schema{
      type: :object,
      properties: %{days: %Schema{type: :integer, minimum: 0, maximum: 90}},
      required: [:days]
    }
end

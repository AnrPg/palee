defmodule PaleeWeb.Schemas.OpenPlatform do
  @moduledoc """
  OpenAPI schemas of the box's «Συνδέσεις» settings, the member's
  marketing-email consent and door access (ADR-378..381). The public API's
  own document is `PaleeWeb.PublicApiSpec`, generated from the operation
  registry.
  """

  alias OpenApiSpex.{MediaType, RequestBody, Schema}

  @uuid %Schema{type: :string, format: :uuid}
  @maybe_uuid %Schema{type: :string, format: :uuid, nullable: true}
  @datetime %Schema{type: :string, format: :"date-time"}
  @maybe_datetime %Schema{type: :string, format: :"date-time", nullable: true}
  @maybe_string %Schema{type: :string, nullable: true}
  @strings %Schema{type: :array, items: %Schema{type: :string}}
  @free %Schema{type: :object, additionalProperties: true}

  def uuid, do: @uuid

  def body(schema),
    do: %RequestBody{required: true, content: %{"application/json" => %MediaType{schema: schema}}}

  def one(key, schema), do: %Schema{type: :object, properties: %{key => schema}, required: [key]}

  def ok do
    %Schema{type: :object, properties: %{ok: %Schema{type: :boolean}}, required: [:ok]}
  end

  # ── Catalog ───────────────────────────────────────────────────────────────

  defp labelled(extra) do
    %Schema{
      type: :object,
      properties:
        Map.merge(
          %{en: %Schema{type: :string}, el: %Schema{type: :string}},
          extra
        ),
      required: [:el, :en]
    }
  end

  def catalog do
    %Schema{
      title: "IntegrationCatalog",
      type: :object,
      properties: %{
        scopes: %Schema{
          type: :array,
          items: labelled(%{scope: %Schema{type: :string}})
        },
        events: %Schema{
          type: :array,
          items: labelled(%{type: %Schema{type: :string}, scope: %Schema{type: :string}})
        },
        audience_providers: @strings
      },
      required: [:audience_providers, :events, :scopes]
    }
  end

  # ── API keys ──────────────────────────────────────────────────────────────

  def api_key do
    %Schema{
      title: "ApiKey",
      type: :object,
      description: "A key's description. The secret itself is never shown again.",
      properties: %{
        id: @uuid,
        name: %Schema{type: :string},
        prefix: %Schema{type: :string},
        masked: %Schema{type: :string, description: "palee_live_ABCD…_••••"},
        scopes: @strings,
        created_by_id: @maybe_uuid,
        created_at: @datetime,
        last_used_at: @maybe_datetime,
        expires_at: @maybe_datetime,
        rotated_at: @maybe_datetime,
        previous_secret_expires_at: %Schema{
          type: :string,
          format: :"date-time",
          nullable: true,
          description: "Until then the secret before the last rotation still works"
        },
        revoked_at: @maybe_datetime,
        status: %Schema{type: :string, enum: ~w(active revoked)}
      },
      required: [:id, :masked, :name, :prefix, :scopes, :status]
    }
  end

  def api_keys, do: one(:keys, %Schema{type: :array, items: api_key()})

  def api_key_secret do
    %Schema{
      title: "ApiKeyWithToken",
      type: :object,
      properties: %{
        key: api_key(),
        token: %Schema{type: :string, description: "Shown once: copy it now"}
      },
      required: [:key, :token]
    }
  end

  def api_key_body do
    %Schema{
      title: "ApiKeyBody",
      type: :object,
      properties: %{
        name: %Schema{type: :string, minLength: 1, maxLength: 80},
        scopes: @strings,
        expires_at: @maybe_datetime
      },
      required: [:name, :scopes]
    }
  end

  # ── Webhooks ──────────────────────────────────────────────────────────────

  def webhook do
    %Schema{
      title: "WebhookEndpoint",
      type: :object,
      properties: %{
        id: @uuid,
        url: %Schema{type: :string},
        description: @maybe_string,
        events: @strings,
        status: %Schema{type: :string, enum: ~w(active disabled)},
        source: %Schema{type: :string, enum: ~w(staff api)},
        api_key_id: @maybe_uuid,
        disabled_reason: @maybe_string,
        consecutive_failures: %Schema{type: :integer},
        last_success_at: @maybe_datetime,
        last_failure_at: @maybe_datetime,
        secret_rotating_until: @maybe_datetime,
        created_at: @datetime
      },
      required: [:events, :id, :source, :status, :url]
    }
  end

  def webhooks, do: one(:webhooks, %Schema{type: :array, items: webhook()})

  def webhook_secret do
    %Schema{
      title: "WebhookEndpointWithSecret",
      type: :object,
      properties: %{
        endpoint: webhook(),
        secret: %Schema{type: :string, description: "The signing secret, shown once"}
      },
      required: [:endpoint, :secret]
    }
  end

  def webhook_body do
    %Schema{
      title: "WebhookEndpointBody",
      type: :object,
      properties: %{
        url: %Schema{type: :string, maxLength: 2000},
        events: @strings,
        description: %Schema{type: :string, maxLength: 200, nullable: true}
      },
      required: [:events, :url]
    }
  end

  def webhook_update_body do
    %Schema{
      title: "WebhookEndpointUpdate",
      type: :object,
      properties: %{
        url: %Schema{type: :string, maxLength: 2000},
        events: @strings,
        description: %Schema{type: :string, maxLength: 200, nullable: true},
        status: %Schema{type: :string, enum: ~w(active disabled)}
      }
    }
  end

  def delivery do
    %Schema{
      title: "WebhookDelivery",
      type: :object,
      properties: %{
        id: @uuid,
        endpoint_id: @uuid,
        event_id: @uuid,
        event_type: %Schema{type: :string},
        status: %Schema{type: :string, enum: ~w(pending succeeded failed)},
        attempts: %Schema{type: :integer},
        next_attempt_at: @maybe_datetime,
        last_status_code: %Schema{type: :integer, nullable: true},
        last_error: @maybe_string,
        delivered_at: @maybe_datetime,
        replay_of_id: @maybe_uuid,
        created_at: @datetime,
        payload: %Schema{type: :object, additionalProperties: true, description: "Detail only"},
        attempts_log: %Schema{
          type: :array,
          description: "Detail only",
          items: %Schema{
            type: :object,
            properties: %{
              attempt: %Schema{type: :integer},
              outcome: %Schema{type: :string},
              status_code: %Schema{type: :integer, nullable: true},
              error: @maybe_string,
              response_excerpt: @maybe_string,
              duration_ms: %Schema{type: :integer, nullable: true},
              started_at: @datetime
            },
            required: [:attempt, :outcome, :started_at]
          }
        }
      },
      required: [:attempts, :endpoint_id, :event_id, :event_type, :id, :status]
    }
  end

  def deliveries do
    %Schema{
      title: "WebhookDeliveryPage",
      type: :object,
      properties: %{
        deliveries: %Schema{type: :array, items: delivery()},
        total: %Schema{type: :integer}
      },
      required: [:deliveries, :total]
    }
  end

  # ── Email list (ADR-380) ──────────────────────────────────────────────────

  def audience_connection do
    %Schema{
      title: "AudienceConnection",
      type: :object,
      nullable: true,
      properties: %{
        provider: %Schema{type: :string, enum: ~w(sandbox mailchimp brevo)},
        list_id: %Schema{type: :string},
        status: %Schema{type: :string, enum: ~w(active invalid)},
        key_saved: %Schema{type: :boolean},
        last_error: @maybe_string,
        last_synced_at: @maybe_datetime,
        sync_requested_at: @maybe_datetime,
        updated_at: @maybe_datetime
      },
      required: [:key_saved, :list_id, :provider, :status]
    }
  end

  def audience, do: one(:connection, audience_connection())

  def audience_body do
    %Schema{
      title: "AudienceConnectionBody",
      type: :object,
      properties: %{
        provider: %Schema{type: :string, enum: ~w(sandbox mailchimp brevo)},
        list_id: %Schema{type: :string, maxLength: 100},
        api_key: %Schema{
          type: :string,
          maxLength: 200,
          description: "Kept encrypted, never shown again; leave out to keep the saved one"
        }
      },
      required: [:list_id, :provider]
    }
  end

  def consent do
    %Schema{
      title: "MarketingConsent",
      type: :object,
      properties: %{
        granted: %Schema{type: :boolean},
        granted_at: @maybe_datetime,
        withdrawn_at: @maybe_datetime,
        text_version: @maybe_string,
        list_connected: %Schema{type: :boolean, description: "Whether the box has an email list"}
      },
      required: [:granted, :list_connected]
    }
  end

  def consent_body do
    %Schema{
      title: "MarketingConsentBody",
      type: :object,
      properties: %{granted: %Schema{type: :boolean}},
      required: [:granted]
    }
  end

  # ── Doors (ADR-381) ───────────────────────────────────────────────────────

  def door_catalog do
    %Schema{
      title: "DoorCatalog",
      type: :object,
      properties: %{
        providers: @strings,
        who: @strings,
        defaults: @free,
        log_days: %Schema{type: :integer}
      },
      required: [:defaults, :log_days, :providers, :who]
    }
  end

  def door do
    %Schema{
      title: "Door",
      type: :object,
      properties: %{
        id: @uuid,
        location_id: @uuid,
        name: %Schema{type: :string},
        provider: %Schema{type: :string, enum: ~w(sandbox shelly kisi)},
        settings: @free,
        rules: @free,
        status: %Schema{type: :string, enum: ~w(active disabled invalid)},
        credentials_saved: %Schema{type: :boolean},
        last_error: @maybe_string,
        last_seen_at: @maybe_datetime,
        updated_at: @maybe_datetime
      },
      required: [:credentials_saved, :id, :location_id, :name, :provider, :rules, :status]
    }
  end

  def doors, do: one(:doors, %Schema{type: :array, items: door()})

  def door_created do
    %Schema{
      title: "DoorWithEventUrl",
      type: :object,
      properties: %{
        door: door(),
        event_url: %Schema{
          type: :string,
          description: "For the controller's own notifications; its token is shown once"
        }
      },
      required: [:door, :event_url]
    }
  end

  def event_url, do: one(:event_url, %Schema{type: :string})

  def door_body do
    %Schema{
      title: "DoorBody",
      type: :object,
      properties: %{
        name: %Schema{type: :string, minLength: 1, maxLength: 80},
        location_id: @uuid,
        provider: %Schema{type: :string, enum: ~w(sandbox shelly kisi)},
        settings: @free,
        credentials: %Schema{
          type: :object,
          additionalProperties: true,
          description: "Written, never read back (Shelly `auth_key`, Kisi `api_key`)"
        },
        rules: @free,
        status: %Schema{type: :string, enum: ~w(active disabled)}
      },
      required: [:location_id, :name, :provider]
    }
  end

  def door_update_body do
    %Schema{
      title: "DoorUpdate",
      type: :object,
      properties: %{
        name: %Schema{type: :string, minLength: 1, maxLength: 80},
        settings: @free,
        credentials: @free,
        rules: @free,
        status: %Schema{type: :string, enum: ~w(active disabled)}
      }
    }
  end

  def access_event do
    %Schema{
      title: "AccessEvent",
      type: :object,
      properties: %{
        id: @uuid,
        door_controller_id: @maybe_uuid,
        location_id: @maybe_uuid,
        user_id: @maybe_uuid,
        actor_id: @maybe_uuid,
        kind: %Schema{
          type: :string,
          enum: ~w(granted denied unlock_failed staff_unlock door_event)
        },
        reason: @maybe_string,
        method: %Schema{type: :string, enum: ~w(qr nfc staff provider)},
        provider_event: @maybe_string,
        person_name: %Schema{type: :string, nullable: true, description: "Who entered or was refused"},
        actor_name: %Schema{type: :string, nullable: true, description: "Who opened from the desk"},
        door_name: %Schema{type: :string, nullable: true},
        occurred_at: @datetime
      },
      required: [:id, :kind, :method, :occurred_at]
    }
  end

  def access_events do
    %Schema{
      title: "AccessEventPage",
      type: :object,
      properties: %{
        events: %Schema{type: :array, items: access_event()},
        total: %Schema{type: :integer}
      },
      required: [:events, :total]
    }
  end

  def open_request do
    %Schema{
      title: "DoorOpenRequest",
      type: :object,
      description:
        "Proof of presence as for the check-in scan: `location_id` + `code` (the door " <>
          "screen's QR), `nfc_code` or `poster_code`; `door_id` when the branch has several doors",
      properties: %{
        location_id: @uuid,
        code: %Schema{type: :string, maxLength: 64},
        nfc_code: %Schema{type: :string, maxLength: 64},
        poster_code: %Schema{type: :string, maxLength: 64},
        door_id: @uuid
      }
    }
  end

  def open_result do
    %Schema{
      title: "DoorOpenResult",
      type: :object,
      properties: %{
        opened: %Schema{type: :boolean},
        reason: %Schema{type: :string, enum: ~w(staff member booked_class open_gym)},
        door: %Schema{
          type: :object,
          properties: %{id: @uuid, name: %Schema{type: :string}},
          required: [:id, :name]
        },
        seconds: %Schema{type: :integer}
      },
      required: [:door, :opened, :reason, :seconds]
    }
  end

  def unlock_result, do: one(:opened, %Schema{type: :boolean})

  def recorded, do: one(:recorded, %Schema{type: :integer})

  def error, do: %Schema{type: :object, additionalProperties: true}
end

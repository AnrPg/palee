defmodule PaleeWeb.Schemas.ServiceStatus do
  @moduledoc "OpenAPI shapes of the public status page and its console (ADR-364)."

  alias OpenApiSpex.{MediaType, RequestBody, Schema}

  @components ~w(app search files email payments fiscal)
  @component_statuses ~w(operational degraded down maintenance unknown)
  @overall ~w(operational degraded partial_outage major_outage maintenance unknown)
  @kinds ~w(incident maintenance)
  @impacts ~w(none minor major critical)
  @incident_statuses ~w(investigating identified monitoring resolved scheduled in_progress completed)
  @probe_statuses ~w(operational degraded down)
  @day_statuses ~w(operational degraded down no_data)

  @en_sources ~w(auto edited)

  defp str(enum), do: %Schema{type: :string, enum: enum}
  defp str_null, do: %Schema{type: :string, nullable: true}
  defp ts, do: %Schema{type: :string, format: :"date-time"}
  defp ts_null, do: %Schema{type: :string, format: :"date-time", nullable: true}

  def component do
    %Schema{
      title: "StatusComponent",
      type: :object,
      properties: %{
        key: str(@components),
        status: str(@component_statuses),
        checked_at: ts_null()
      },
      required: [:checked_at, :key, :status]
    }
  end

  def incident_update do
    %Schema{
      title: "StatusIncidentUpdate",
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        status: str(@incident_statuses),
        body: %Schema{type: :string},
        locale: str_null(),
        body_en: str_null(),
        en_source: %Schema{type: :string, enum: @en_sources, nullable: true},
        published_by: %Schema{
          type: :string,
          nullable: true,
          description: "Who published this step (console only)"
        },
        created_at: ts()
      },
      required: [:body, :body_en, :created_at, :en_source, :id, :locale, :status]
    }
  end

  def incident do
    %Schema{
      title: "StatusIncident",
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        kind: str(@kinds),
        title: %Schema{type: :string},
        impact: str(@impacts),
        status: str(@incident_statuses),
        components: %Schema{type: :array, items: str(@components)},
        scheduled_for: ts_null(),
        scheduled_until: ts_null(),
        started_at: ts(),
        resolved_at: ts_null(),
        locale: str_null(),
        title_en: str_null(),
        en_source: %Schema{type: :string, enum: @en_sources, nullable: true},
        published_by: %Schema{
          type: :string,
          nullable: true,
          description: "Who published the incident (console only)"
        },
        updates: %Schema{type: :array, items: incident_update()}
      },
      required: [
        :components,
        :en_source,
        :id,
        :impact,
        :kind,
        :locale,
        :resolved_at,
        :scheduled_for,
        :scheduled_until,
        :started_at,
        :status,
        :title,
        :title_en,
        :updates
      ]
    }
  end

  def overview do
    %Schema{
      title: "StatusOverview",
      type: :object,
      properties: %{
        status: str(@overall),
        components: %Schema{type: :array, items: component()},
        active: %Schema{type: :array, items: incident()},
        upcoming: %Schema{type: :array, items: incident()},
        generated_at: ts()
      },
      required: [:active, :components, :generated_at, :status, :upcoming]
    }
  end

  def history do
    day = %Schema{
      title: "StatusHistoryDay",
      type: :object,
      properties: %{
        date: %Schema{type: :string, format: :date},
        status: str(@day_statuses),
        uptime_percent: %Schema{type: :number, nullable: true}
      },
      required: [:date, :status, :uptime_percent]
    }

    %Schema{
      title: "StatusHistory",
      type: :object,
      properties: %{
        days: %Schema{type: :integer},
        from: %Schema{type: :string, format: :date},
        to: %Schema{type: :string, format: :date},
        components: %Schema{
          type: :array,
          items: %Schema{
            title: "StatusComponentHistory",
            type: :object,
            properties: %{
              key: str(@components),
              uptime_percent: %Schema{type: :number, nullable: true},
              days: %Schema{type: :array, items: day}
            },
            required: [:days, :key, :uptime_percent]
          }
        },
        incidents: %Schema{type: :array, items: incident()},
        generated_at: ts()
      },
      required: [:components, :days, :from, :generated_at, :incidents, :to]
    }
  end

  def console do
    probe = %Schema{
      title: "StatusProbeState",
      type: :object,
      properties: %{
        key: %Schema{type: :string},
        status: str(@probe_statuses),
        reason: %Schema{type: :string, nullable: true},
        checked_at: ts(),
        changed_at: ts()
      },
      required: [:changed_at, :checked_at, :key, :reason, :status]
    }

    %Schema{
      title: "StatusConsole",
      type: :object,
      properties: %{
        probes: %Schema{type: :array, items: probe},
        incidents: %Schema{type: :array, items: incident()},
        subscribers: %Schema{
          type: :object,
          properties: %{
            confirmed: %Schema{type: :integer},
            waiting: %Schema{type: :integer}
          },
          required: [:confirmed, :waiting]
        }
      },
      required: [:incidents, :probes, :subscribers]
    }
  end

  def incident_body do
    body(
      %Schema{
        title: "StatusIncidentCreate",
        type: :object,
        properties: %{
          kind: str(@kinds),
          title: %Schema{type: :string, minLength: 3, maxLength: 140},
          impact: str(@impacts),
          status: str(@incident_statuses),
          components: %Schema{type: :array, items: str(@components)},
          scheduled_for: ts(),
          scheduled_until: ts(),
          body: %Schema{type: :string, minLength: 1, maxLength: 2000},
          notify: %Schema{type: :boolean},
          locale: %Schema{type: :string, maxLength: 8},
          title_en: %Schema{type: :string, maxLength: 140},
          body_en: %Schema{type: :string, maxLength: 2000},
          en_source: str(@en_sources)
        },
        required: [:body, :title]
      },
      "A new incident or planned maintenance with its first note"
    )
  end

  def update_body do
    body(
      %Schema{
        title: "StatusIncidentUpdateCreate",
        type: :object,
        properties: %{
          status: str(@incident_statuses),
          body: %Schema{type: :string, minLength: 1, maxLength: 2000},
          notify: %Schema{type: :boolean},
          locale: %Schema{type: :string, maxLength: 8},
          body_en: %Schema{type: :string, maxLength: 2000},
          en_source: str(@en_sources)
        },
        required: [:body]
      },
      "A new step in the timeline"
    )
  end

  def edit_body do
    body(
      %Schema{
        title: "StatusIncidentEdit",
        type: :object,
        properties: %{
          title: %Schema{type: :string, minLength: 3, maxLength: 140},
          impact: str(@impacts),
          components: %Schema{type: :array, items: str(@components)}
        }
      },
      "A correction (no note, no email)"
    )
  end

  def translate_body do
    body(
      %Schema{
        title: "StatusTranslate",
        type: :object,
        properties: %{
          title: %Schema{type: :string, maxLength: 140},
          body: %Schema{type: :string, minLength: 1, maxLength: 2000}
        },
        required: [:body]
      },
      "The title and note to preview in English"
    )
  end

  def translation do
    %Schema{
      title: "StatusTranslation",
      type: :object,
      properties: %{
        locale: %Schema{
          type: :string,
          nullable: true,
          description: "The detected language of the text"
        },
        title: str_null(),
        body: %Schema{type: :string}
      },
      required: [:body, :locale, :title]
    }
  end

  def subscribe_body do
    body(
      %Schema{
        title: "StatusSubscribe",
        type: :object,
        properties: %{
          email: %Schema{type: :string, format: :email, maxLength: 254},
          locale: %Schema{type: :string, maxLength: 8}
        },
        required: [:email]
      },
      "The address that wants status emails"
    )
  end

  def token_body do
    body(
      %Schema{
        title: "StatusToken",
        type: :object,
        properties: %{token: %Schema{type: :string, minLength: 1, maxLength: 512}},
        required: [:token]
      },
      "The token from the email"
    )
  end

  def accepted do
    %Schema{
      title: "StatusAccepted",
      type: :object,
      properties: %{status: %Schema{type: :string, enum: ["accepted", "confirmed", "removed"]}},
      required: [:status]
    }
  end

  defp body(schema, description) do
    %RequestBody{
      description: description,
      required: true,
      content: %{"application/json" => %MediaType{schema: schema}}
    }
  end
end

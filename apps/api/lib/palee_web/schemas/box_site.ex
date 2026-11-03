defmodule PaleeWeb.Schemas.BoxSite do
  @moduledoc "OpenAPI schemas of the box's website and Google review asks (ADR-352..355)."

  alias OpenApiSpex.{MediaType, RequestBody, Schema}
  alias PaleeWeb.Schemas.BoxReviews

  @uuid %Schema{type: :string, format: :uuid}
  @time %Schema{type: :string, format: :"date-time", nullable: true}
  @text %Schema{type: :string, nullable: true}
  @int %Schema{type: :integer}
  @bool %Schema{type: :boolean}

  @section_keys ~w(hero about schedule events wod packages coaches location reviews faq trial_form contact_form)
  @domain_statuses ~w(pending_dns pending_tls active broken expired)
  # ADR-398 (`BoxSite.Domain.IngressPolicy`).
  @certificate_statuses ~w(none pending issuing active failed)
  @certificate_errors ~w(cluster_refused cluster_unreachable challenge_failed rate_limited
                         issuer_not_ready issuance_failed)
  @consent_actions ~w(accept_all reject_all custom withdraw)
  @review_actions ~w(opened later dismissed)

  def body(schema),
    do: %RequestBody{required: true, content: %{"application/json" => %MediaType{schema: schema}}}

  defp section, do: %Schema{type: :string, enum: @section_keys}
  defp sections, do: %Schema{type: :array, items: section()}

  defp faq_entry do
    %Schema{
      title: "SiteFaqEntry",
      type: :object,
      properties: %{
        question: %Schema{type: :string, maxLength: 200},
        answer: %Schema{type: :string, maxLength: 1000},
        question_en: %Schema{
          type: :string,
          maxLength: 200,
          description: "Optional English text (ADR-388)"
        },
        answer_en: %Schema{
          type: :string,
          maxLength: 1000,
          description: "Optional English text (ADR-388)"
        }
      },
      required: [:answer, :question]
    }
  end

  defp faq, do: %Schema{type: :array, items: faq_entry(), maxItems: 12}

  defp tags do
    %Schema{
      title: "SiteTags",
      type: :object,
      description: "Public tag ids; none loads before the visitor's consent (ADR-354)",
      properties: %{
        meta_pixel_id: @text,
        ga4_measurement_id: @text,
        gtm_container_id: @text
      },
      required: [:ga4_measurement_id, :gtm_container_id, :meta_pixel_id]
    }
  end

  # ── Admin ────────────────────────────────────────────────────────────────

  def settings do
    %Schema{
      title: "SiteSettings",
      type: :object,
      properties: %{
        section_order: sections(),
        hidden_sections: sections(),
        public_schedule: @bool,
        public_wod: %Schema{type: :boolean, description: "«WOD της ημέρας» on the site (ADR-388)"},
        about_en: %Schema{type: :string, nullable: true, maxLength: 4000},
        faq: faq(),
        forms_enabled: @bool,
        meta_pixel_id: @text,
        ga4_measurement_id: @text,
        gtm_container_id: @text,
        banner_version: @int,
        conversions_api_enabled: @bool,
        has_conversions_api_token: %Schema{
          type: :boolean,
          description: "A token is saved; the token itself is never returned"
        },
        lock_version: @int
      },
      required: [
        :about_en,
        :banner_version,
        :conversions_api_enabled,
        :faq,
        :forms_enabled,
        :ga4_measurement_id,
        :gtm_container_id,
        :has_conversions_api_token,
        :hidden_sections,
        :lock_version,
        :meta_pixel_id,
        :public_schedule,
        :public_wod,
        :section_order
      ]
    }
  end

  def settings_update do
    %Schema{
      title: "SiteSettingsUpdate",
      type: :object,
      properties: %{
        section_order: sections(),
        hidden_sections: sections(),
        public_schedule: @bool,
        public_wod: @bool,
        about_en: %Schema{type: :string, nullable: true, maxLength: 4000},
        faq: faq(),
        forms_enabled: @bool,
        meta_pixel_id: @text,
        ga4_measurement_id: @text,
        gtm_container_id: @text,
        conversions_api_enabled: @bool,
        conversions_api_token: %Schema{
          type: :string,
          nullable: true,
          writeOnly: true,
          description: "Meta Conversions API access token (write-only; empty removes it)"
        },
        lock_version: @int
      },
      required: [:lock_version]
    }
  end

  defp dns_record do
    %Schema{
      title: "SiteDnsRecord",
      type: :object,
      properties: %{
        type: %Schema{type: :string, enum: ~w(TXT CNAME A)},
        name: %Schema{type: :string},
        value: %Schema{type: :string}
      },
      required: [:name, :type, :value]
    }
  end

  def domain do
    %Schema{
      title: "SiteDomain",
      type: :object,
      properties: %{
        id: @uuid,
        host: %Schema{type: :string},
        primary: @bool,
        status: %Schema{type: :string, enum: @domain_statuses},
        last_error: %Schema{
          type: :string,
          nullable: true,
          enum: ["dns_txt_missing", "dns_not_pointing", "tls_not_ready", "tls_failed", nil]
        },
        checked_at: @time,
        next_check_at: @time,
        verified_at: @time,
        active_at: @time,
        certificate_status: %Schema{
          type: :string,
          enum: @certificate_statuses,
          description:
            "ADR-398: the host's certificate (none until DNS is proven, then pending, issuing, active or failed)"
        },
        certificate_error: %Schema{
          type: :string,
          nullable: true,
          enum: @certificate_errors ++ [nil]
        },
        dns_records: %Schema{type: :array, items: dns_record()}
      },
      required: [
        :active_at,
        :certificate_error,
        :certificate_status,
        :checked_at,
        :dns_records,
        :host,
        :id,
        :last_error,
        :next_check_at,
        :primary,
        :status,
        :verified_at
      ]
    }
  end

  def admin_site_response do
    %Schema{
      title: "AdminSiteResponse",
      type: :object,
      properties: %{
        settings: settings(),
        section_keys: sections(),
        domains: %Schema{type: :array, items: domain()}
      },
      required: [:domains, :section_keys, :settings]
    }
  end

  def settings_response do
    %Schema{
      title: "SiteSettingsResponse",
      type: :object,
      properties: %{settings: settings()},
      required: [:settings]
    }
  end

  def domain_request do
    %Schema{
      title: "SiteDomainRequest",
      type: :object,
      properties: %{host: %Schema{type: :string, maxLength: 260}},
      required: [:host]
    }
  end

  def domain_response do
    %Schema{
      title: "SiteDomainResponse",
      type: :object,
      properties: %{domain: domain()},
      required: [:domain]
    }
  end

  def domains_response do
    %Schema{
      title: "SiteDomainsResponse",
      type: :object,
      properties: %{domains: %Schema{type: :array, items: domain()}},
      required: [:domains]
    }
  end

  def summary_response do
    count = @int

    %Schema{
      title: "SiteSummaryResponse",
      type: :object,
      properties: %{
        days: @int,
        submissions: %Schema{
          type: :object,
          properties: %{total: count, delivered: count, waiting: count, failed: count},
          required: [:delivered, :failed, :total, :waiting]
        },
        consents: %Schema{
          type: :object,
          properties: %{accept_all: count, reject_all: count, custom: count, withdraw: count},
          required: [:accept_all, :custom, :reject_all, :withdraw]
        }
      },
      required: [:consents, :days, :submissions]
    }
  end

  def ops_domains_response do
    %Schema{
      title: "SiteOpsDomainsResponse",
      type: :object,
      properties: %{
        cname_target: %Schema{type: :string},
        domains: %Schema{
          type: :array,
          items: %Schema{
            type: :object,
            properties: %{
              host: %Schema{type: :string},
              slug: %Schema{type: :string},
              status: %Schema{type: :string, enum: @domain_statuses},
              verified_at: @time,
              updated_at: @time
            },
            required: [:host, :slug, :status, :updated_at, :verified_at]
          }
        }
      },
      required: [:cname_target, :domains]
    }
  end

  # ── Public ───────────────────────────────────────────────────────────────

  def public_site do
    %Schema{
      title: "PublicSiteResponse",
      type: :object,
      properties: %{
        slug: %Schema{type: :string},
        canonical_url: %Schema{type: :string},
        sections: sections(),
        faq: faq(),
        forms: %Schema{
          type: :object,
          properties: %{
            trial: @bool,
            contact: @bool,
            kinds: %Schema{type: :array, items: %Schema{type: :string, enum: ~w(trial contact)}}
          },
          required: [:contact, :kinds, :trial]
        },
        reviews: BoxReviews.site_reviews(),
        report_contact: %Schema{
          type: :string,
          nullable: true,
          description: "Palee's address for reporting content on the site (ADR-397, DSA Art. 16)"
        },
        language: %Schema{type: :string, description: "The box's language (ADR-388)"},
        languages: %Schema{
          type: :array,
          items: %Schema{type: :string},
          description: "The site's languages: the box's own and English"
        },
        time_zone: %Schema{type: :string},
        about_en: %Schema{type: :string, nullable: true},
        events: %Schema{type: :array, items: BoxReviews.site_event()},
        wod: %Schema{type: :array, items: BoxReviews.site_wod()},
        tracking: %Schema{
          type: :object,
          properties: %{
            tags: tags(),
            consent_required: @bool,
            banner_version: @int,
            categories: %Schema{
              type: :array,
              items: %Schema{type: :string, enum: ~w(necessary analytics marketing)}
            },
            validity_days: @int
          },
          required: [:banner_version, :categories, :consent_required, :tags, :validity_days]
        },
        timetable: %Schema{
          type: :array,
          description:
            "The next 7 days' classes when the owner shows the timetable (no spots or people)",
          items: %Schema{
            title: "SiteTimetableClass",
            type: :object,
            properties: %{
              id: @uuid,
              name: %Schema{type: :string},
              class_type_id: %{@uuid | nullable: true},
              scheduled_at: %Schema{type: :string, format: :"date-time"},
              duration_minutes: @int,
              location_id: %{@uuid | nullable: true}
            },
            required: [:class_type_id, :duration_minutes, :id, :location_id, :name, :scheduled_at]
          }
        }
      },
      required: [
        :about_en,
        :canonical_url,
        :events,
        :faq,
        :forms,
        :language,
        :languages,
        :report_contact,
        :reviews,
        :sections,
        :slug,
        :time_zone,
        :timetable,
        :tracking,
        :wod
      ]
    }
  end

  def by_host_response do
    %Schema{
      title: "SiteByHostResponse",
      type: :object,
      properties: %{
        slug: %Schema{type: :string},
        host: %Schema{type: :string},
        primary: @bool,
        primary_host: @text
      },
      required: [:host, :primary, :primary_host, :slug]
    }
  end

  def form_request do
    %Schema{
      title: "SiteFormRequest",
      type: :object,
      properties: %{
        name: %Schema{type: :string, maxLength: 200},
        email: %Schema{type: :string, nullable: true, maxLength: 320},
        phone: %Schema{type: :string, nullable: true, maxLength: 40},
        message: %Schema{type: :string, nullable: true, maxLength: 4000},
        preferred_time: %Schema{type: :string, nullable: true, maxLength: 200},
        class_type_id: %{@uuid | nullable: true},
        locale: %Schema{type: :string, nullable: true, maxLength: 10},
        marketing_opt_in: %Schema{
          type: :boolean,
          description: "Separate, unticked opt-in to marketing follow-ups"
        },
        privacy_ack: %Schema{type: :boolean, description: "Must be true"},
        visitor_id: %{@uuid | nullable: true},
        event_id: %{
          @uuid
          | nullable: true,
            description:
              "The browser Pixel's eventID for the same Lead, so Meta counts the Conversions API event once"
        },
        consent_text_version: %Schema{type: :string, nullable: true, maxLength: 40},
        consent_text_hash: %Schema{type: :string, nullable: true, maxLength: 80},
        attribution: %Schema{
          type: :object,
          properties:
            Map.new(
              ~w(utm_source utm_medium utm_campaign utm_term utm_content referrer_host landing_path)a,
              &{&1, %Schema{type: :string, maxLength: 500}}
            )
        },
        website: %Schema{type: :string, nullable: true, description: "Honeypot: leave empty"},
        elapsed_ms: %Schema{type: :integer, nullable: true, description: "Time spent on the form"}
      },
      required: [:name, :privacy_ack]
    }
  end

  def form_response do
    %Schema{
      title: "SiteFormResponse",
      type: :object,
      properties: %{status: %Schema{type: :string, enum: ["received"]}},
      required: [:status]
    }
  end

  def consent_request do
    %Schema{
      title: "SiteConsentRequest",
      type: :object,
      properties: %{
        visitor_id: @uuid,
        banner_version: @int,
        action: %Schema{type: :string, enum: @consent_actions},
        analytics: @bool,
        marketing: @bool
      },
      required: [:action, :banner_version, :visitor_id]
    }
  end

  def consent_response do
    %Schema{
      title: "SiteConsentResponse",
      type: :object,
      properties: %{
        analytics: @bool,
        marketing: @bool,
        banner_version: @int,
        expires_at: %Schema{type: :string, format: :"date-time"},
        allowed_tags: %Schema{
          type: :array,
          items: %Schema{
            type: :string,
            enum: ~w(ga4_measurement_id meta_pixel_id gtm_container_id)
          }
        }
      },
      required: [:allowed_tags, :analytics, :banner_version, :expires_at, :marketing]
    }
  end

  # ── Review asks ──────────────────────────────────────────────────────────

  def review_settings do
    %Schema{
      title: "ReviewAskSettings",
      type: :object,
      properties: %{
        google_place_id: @text,
        enabled: @bool,
        milestones: %Schema{type: :array, items: @int},
        lock_version: @int,
        google_review_url: @text
      },
      required: [:enabled, :google_place_id, :google_review_url, :lock_version, :milestones]
    }
  end

  def review_settings_update do
    %Schema{
      title: "ReviewAskSettingsUpdate",
      type: :object,
      properties: %{
        google_place_id: %Schema{type: :string, nullable: true, maxLength: 300},
        enabled: @bool,
        milestones: %Schema{
          type: :array,
          items: %Schema{type: :integer, minimum: 3, maximum: 1000},
          minItems: 1,
          maxItems: 6
        },
        lock_version: @int
      },
      required: [:lock_version]
    }
  end

  def review_settings_response do
    %Schema{
      title: "ReviewAskSettingsResponse",
      type: :object,
      properties: %{settings: review_settings(), google: BoxReviews.google()},
      required: [:google, :settings]
    }
  end

  def review_summary_response do
    count = @int

    %Schema{
      title: "ReviewAskSummaryResponse",
      type: :object,
      properties: %{
        days: @int,
        counts: %Schema{
          type: :object,
          properties: %{
            asked: count,
            opened: count,
            later: count,
            dismissed: count,
            unanswered: count,
            opted_out: count
          },
          required: [:asked, :dismissed, :later, :opened, :opted_out, :unanswered]
        }
      },
      required: [:counts, :days]
    }
  end

  def review_ask do
    %Schema{
      title: "ReviewAsk",
      type: :object,
      properties: %{
        id: @uuid,
        milestone: @int,
        status: %Schema{type: :string, enum: ["shown" | @review_actions]},
        shown_at: %Schema{type: :string, format: :"date-time"},
        google_review_url: @text,
        has_review: %Schema{
          type: :boolean,
          description: "The member already wrote an in-app review (ADR-386)"
        },
        actions: %Schema{type: :array, items: %Schema{type: :string, enum: @review_actions}}
      },
      required: [:actions, :google_review_url, :has_review, :id, :milestone, :shown_at, :status]
    }
  end

  def review_ask_response do
    %Schema{
      title: "ReviewAskResponse",
      type: :object,
      properties: %{ask: %{review_ask() | nullable: true}},
      required: [:ask]
    }
  end

  def review_respond_request do
    %Schema{
      title: "ReviewAskRespondRequest",
      type: :object,
      properties: %{action: %Schema{type: :string, enum: @review_actions}},
      required: [:action]
    }
  end

  def review_opt_out_response do
    %Schema{
      title: "ReviewAskOptOutResponse",
      type: :object,
      properties: %{opted_out: @bool},
      required: [:opted_out]
    }
  end
end

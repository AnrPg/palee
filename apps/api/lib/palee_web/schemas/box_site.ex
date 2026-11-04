defmodule PaleeWeb.Schemas.BoxSite do
  @moduledoc "OpenAPI schemas of the box's website and Google review asks (ADR-352..355)."

  alias OpenApiSpex.{MediaType, RequestBody, Schema}
  alias PaleeWeb.Schemas.BoxReviews

  @uuid %Schema{type: :string, format: :uuid}
  @time %Schema{type: :string, format: :"date-time", nullable: true}
  @text %Schema{type: :string, nullable: true}
  @int %Schema{type: :integer}
  @bool %Schema{type: :boolean}

  @section_keys ~w(hero about photos stats schedule events wod programmes packages coaches location reviews faq trial_form contact_form)
  # ADR-530: the keys only; colours live in the web.
  @templates ~w(arena tiles stories atelier)
  @palettes ~w(palee electric flame sun amber emerald aegean violet fuchsia olive navy mono)
  @appearances ~w(auto light dark)
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
        id: %Schema{
          type: :string,
          format: :uuid,
          description: "Stable id (ADR-520); a new entry gets one when saved"
        },
        question: %Schema{type: :string, maxLength: 200},
        answer: %Schema{type: :string, maxLength: 1000}
      },
      required: [:answer, :question]
    }
  end

  defp faq, do: %Schema{type: :array, items: faq_entry(), maxItems: 12}

  defp template, do: %Schema{type: :string, enum: @templates, description: "ADR-530 template"}
  defp palette, do: %Schema{type: :string, enum: @palettes, description: "ADR-530 palette key"}

  defp appearance,
    do: %Schema{
      type: :string,
      enum: @appearances,
      description: "«Αυτόματα», «Πάντα φωτεινή» or «Πάντα σκοτεινή»"
    }

  defp calm_motion,
    do: %Schema{type: :boolean, description: "«Λιγότερη κίνηση»: the site's motion is off"}

  # ADR-530 §2: what waits for «Δημοσίευση»; only the fields that differ
  # from the live site are present.
  defp draft do
    %Schema{
      title: "SiteDraft",
      type: :object,
      nullable: true,
      description: "The publishable fields waiting for «Δημοσίευση»; null when nothing waits",
      properties: %{
        template: template(),
        palette: palette(),
        appearance: appearance(),
        calm_motion: calm_motion(),
        hidden_sections: sections(),
        public_schedule: @bool,
        public_wod: @bool
      }
    }
  end

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
        faq: faq(),
        translation_locales: locales("Languages the box translates its texts into (ADR-520)"),
        visible_locales: locales("Translations visitors can pick on the site (ADR-520)"),
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
        template: template(),
        palette: palette(),
        appearance: appearance(),
        calm_motion: calm_motion(),
        draft: draft(),
        published_at: %{@time | description: "The last «Δημοσίευση» (ADR-530)"},
        template_notice: %Schema{
          type: :boolean,
          description: "The site moved to «Αρένα» (ADR-530); shown until published or dismissed"
        },
        lock_version: @int
      },
      required: [
        :appearance,
        :banner_version,
        :calm_motion,
        :conversions_api_enabled,
        :draft,
        :faq,
        :forms_enabled,
        :ga4_measurement_id,
        :gtm_container_id,
        :has_conversions_api_token,
        :hidden_sections,
        :lock_version,
        :meta_pixel_id,
        :palette,
        :public_schedule,
        :public_wod,
        :published_at,
        :section_order,
        :template,
        :template_notice,
        :translation_locales,
        :visible_locales
      ]
    }
  end

  defp locales(description) do
    %Schema{
      type: :array,
      maxItems: 11,
      items: %Schema{type: :string, maxLength: 10},
      description: description
    }
  end

  def settings_update do
    %Schema{
      title: "SiteSettingsUpdate",
      type: :object,
      description:
        "ADR-530: template, palette, appearance, calm_motion, hidden_sections, public_schedule and public_wod go into the draft; the rest saves at once",
      properties: %{
        section_order: sections(),
        hidden_sections: sections(),
        public_schedule: @bool,
        public_wod: @bool,
        template: template(),
        palette: palette(),
        appearance: appearance(),
        calm_motion: calm_motion(),
        faq: faq(),
        translation_locales: locales("Languages to translate into; the box's own is left out"),
        visible_locales:
          locales("Translations visitors can pick; a subset of translation_locales"),
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
        type: %Schema{
          type: :string,
          enum: ~w(TXT CNAME ALIAS),
          description:
            "ALIAS: an apex host's CNAME flattening / ALIAS / ANAME to the value (ADR-398)"
        },
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
        domains: %Schema{type: :array, items: domain()},
        languages: site_languages()
      },
      required: [:domains, :languages, :section_keys, :settings]
    }
  end

  def settings_response do
    %Schema{
      title: "SiteSettingsResponse",
      type: :object,
      properties: %{settings: settings(), languages: site_languages()},
      required: [:languages, :settings]
    }
  end

  def settings_only_response do
    %Schema{
      title: "SiteSettingsOnlyResponse",
      type: :object,
      description:
        "ADR-530: the settings after «Δημοσίευση», a discarded draft or a hidden notice",
      properties: %{settings: settings()},
      required: [:settings]
    }
  end

  # ── Translations (ADR-520) ───────────────────────────────────────────────

  @translation_statuses ~w(missing stale machine ok)
  @translation_groups ~w(about rooms faq packages classes events locations)
  @translation_kinds ~w(box_profile class_type event location package site_faq space)

  defp status_counts do
    %Schema{
      title: "SiteTranslationCounts",
      type: :object,
      properties: Map.new(@translation_statuses, &{String.to_atom(&1), @int}),
      required: Enum.map(@translation_statuses, &String.to_atom/1)
    }
  end

  defp site_languages do
    %Schema{
      title: "SiteLanguages",
      type: :object,
      description: "The site's own language, the ones it can add and each translation's progress",
      properties: %{
        source: %Schema{type: :string, description: "The box's own language (the source)"},
        available: %Schema{type: :array, items: %Schema{type: :string}},
        machine_available: @bool,
        progress: %Schema{
          type: :array,
          items: %Schema{
            title: "SiteLanguageProgress",
            type: :object,
            properties: %{
              locale: %Schema{type: :string},
              counts: status_counts(),
              total: @int
            },
            required: [:counts, :locale, :total]
          }
        }
      },
      required: [:available, :machine_available, :progress, :source]
    }
  end

  defp translation_item do
    %Schema{
      title: "SiteTranslationItem",
      type: :object,
      properties: %{
        key: %Schema{type: :string, description: "kind:id:field"},
        kind: %Schema{type: :string, enum: @translation_kinds},
        id: @uuid,
        field: %Schema{type: :string},
        group: %Schema{type: :string, enum: @translation_groups},
        label: %Schema{
          type: :string,
          nullable: true,
          description: "What the text belongs to (a package's name, an FAQ number)"
        },
        source: %Schema{type: :string, description: "The box's own text"},
        text: %Schema{type: :string, nullable: true, description: "The translation"},
        status: %Schema{type: :string, enum: @translation_statuses},
        origin: %Schema{type: :string, enum: ~w(manual machine), nullable: true},
        updated_at: @time
      },
      required: [
        :field,
        :group,
        :id,
        :key,
        :kind,
        :label,
        :origin,
        :source,
        :status,
        :text,
        :updated_at
      ]
    }
  end

  def translations_response do
    %Schema{
      title: "SiteTranslationsResponse",
      type: :object,
      properties: %{
        locale: %Schema{type: :string},
        source_language: %Schema{type: :string},
        machine_available: @bool,
        counts: status_counts(),
        total: @int,
        written: %Schema{type: :integer, description: "Texts the machine wrote (machine only)"},
        items: %Schema{type: :array, items: translation_item()}
      },
      required: [:counts, :items, :locale, :machine_available, :source_language, :total]
    }
  end

  def translations_save_request do
    %Schema{
      title: "SiteTranslationsSave",
      type: :object,
      properties: %{
        locale: %Schema{type: :string, maxLength: 10},
        entries: %Schema{
          type: :array,
          minItems: 1,
          maxItems: 200,
          items: %Schema{
            title: "SiteTranslationEdit",
            type: :object,
            properties: %{
              kind: %Schema{type: :string, enum: @translation_kinds},
              id: @uuid,
              field: %Schema{type: :string, maxLength: 40},
              text: %Schema{
                type: :string,
                nullable: true,
                maxLength: 4000,
                description: "Empty or null removes the translation"
              }
            },
            required: [:field, :id, :kind, :text]
          }
        }
      },
      required: [:entries, :locale]
    }
  end

  def translations_keep_request do
    %Schema{
      title: "SiteTranslationsKeep",
      type: :object,
      properties: %{
        locale: %Schema{type: :string, maxLength: 10},
        keys: %Schema{
          type: :array,
          minItems: 1,
          maxItems: 500,
          items: %Schema{type: :string, maxLength: 200}
        }
      },
      required: [:keys, :locale]
    }
  end

  def translations_machine_request do
    %Schema{
      title: "SiteTranslationsMachine",
      type: :object,
      properties: %{locale: %Schema{type: :string, maxLength: 10}},
      required: [:locale]
    }
  end

  def translation_locale do
    %Schema{
      type: :string,
      maxLength: 10,
      description: "A language of the app, e.g. en, de, pt-PT"
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
          description: "The site's languages: the box's own first, then its visible translations"
        },
        translation: %Schema{
          type: :string,
          nullable: true,
          description: "The translation this answer is in (ADR-520), null for the box's own"
        },
        time_zone: %Schema{type: :string},
        about: %Schema{
          type: :string,
          nullable: true,
          description: "The translated «Σχετικά», null when there is none"
        },
        texts: %Schema{
          type: :object,
          additionalProperties: %Schema{type: :string},
          description: "Translations of texts served by other reads, keyed kind:id:field"
        },
        class_type_names: %Schema{
          type: :object,
          additionalProperties: %Schema{type: :string},
          description: "Translated class names by the box's own name"
        },
        template: template(),
        palette: palette(),
        appearance: appearance(),
        calm_motion: calm_motion(),
        phone: %Schema{
          type: :string,
          nullable: true,
          description: "The box's public phone; null while the box has none (ADR-530)"
        },
        photos: site_photos(),
        stats: site_stats(),
        programmes: %Schema{
          type: :array,
          items: site_programme(),
          description: "«Προγράμματα» for sale (ADR-530 §3); empty while there is none"
        },
        programmes_total: %{
          @int
          | description: "How many programmes the box sells (ADR-543), for «Όλα τα προγράμματα (N)»"
        },
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
        :about,
        :appearance,
        :calm_motion,
        :canonical_url,
        :class_type_names,
        :events,
        :faq,
        :forms,
        :language,
        :languages,
        :palette,
        :phone,
        :photos,
        :programmes,
        :programmes_total,
        :report_contact,
        :reviews,
        :sections,
        :slug,
        :stats,
        :template,
        :texts,
        :time_zone,
        :timetable,
        :tracking,
        :translation,
        :wod
      ]
    }
  end

  # ── ADR-530 sections ─────────────────────────────────────────────────────

  @nullable_int %Schema{type: :integer, nullable: true}

  defp site_photos do
    %Schema{
      title: "SitePhotos",
      type: :object,
      description: "«Φωτογραφίες»: page photos then public room photos (at most 12)",
      properties: %{
        items: %Schema{
          type: :array,
          maxItems: 12,
          items: %Schema{
            title: "SitePhoto",
            type: :object,
            properties: %{
              id: @uuid,
              url: %Schema{type: :string},
              width: @nullable_int,
              height: @nullable_int,
              caption: %Schema{
                type: :string,
                nullable: true,
                description: "Null for the page's photos; the photo's caption or room's name"
              }
            },
            required: [:caption, :height, :id, :url, :width]
          }
        },
        video: %Schema{
          title: "SiteVideo",
          type: :object,
          nullable: true,
          description: "Null until boxes can add a site video",
          properties: %{
            url: %Schema{type: :string},
            poster_url: %Schema{type: :string, nullable: true}
          },
          required: [:poster_url, :url]
        }
      },
      required: [:items, :video]
    }
  end

  defp site_stats do
    %Schema{
      title: "SiteStats",
      type: :object,
      nullable: true,
      description:
        "«Αριθμοί κοινότητας»: aggregates only, null when the section is off; a zero or null is not shown",
      properties: %{
        classes_per_week: %{@nullable_int | description: "Classes over the next 7 days"},
        prs_this_year: %{@nullable_int | description: "PRs recorded in the box this year"},
        years_open: %{@nullable_int | description: "Whole years since the box joined"}
      },
      required: [:classes_per_week, :prs_this_year, :years_open]
    }
  end

  defp site_programme do
    %Schema{
      title: "SiteProgramme",
      type: :object,
      properties: %{
        id: @uuid,
        title: %Schema{type: :string},
        summary: @text,
        weeks: @nullable_int,
        price_cents: @nullable_int,
        currency: @text,
        cover_url: @text,
        sessions_per_week: @nullable_int,
        level: @text,
        rating_average: %Schema{type: :number, nullable: true},
        rating_count: @int,
        url: @text
      },
      required: [
        :cover_url,
        :currency,
        :id,
        :level,
        :price_cents,
        :rating_average,
        :rating_count,
        :sessions_per_week,
        :summary,
        :title,
        :url,
        :weeks
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
